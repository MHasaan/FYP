"""
GroundingDINO Service

Standalone service that processes Visual Search requests independently of
the live frame pipeline. Subscribes to Redis channel 'grounding_dino:requests',
runs open-set object detection on the input (image or video), and publishes
results to 'grounding_dino:results' for the backend's
GroundingDinoResultProcessor to persist.

Design notes:
  - Runs in its own daemon thread alongside PipelineManager. Does NOT share
    the per-instance frame pipelines — those are tuned for low-latency
    streaming and would be wrecked by GDINO's heavier per-image inference.
  - Model is loaded lazily on the first job, then cached. If no Visual
    Search requests ever come in, no model weight gets loaded.
  - Inference is gated by a STUB toggle (GDINO_USE_STUB env var). With the
    stub enabled, returns deterministic fake detections so the full
    backend ↔ ML manager ↔ frontend flow can be tested without the heavy
    CUDA-op build. Set GDINO_USE_STUB=0 once the real model is wired in.
"""

import json
import os
import threading
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

import cv2
import numpy as np
import redis
from redis.exceptions import ConnectionError, TimeoutError


REQUESTS_CHANNEL = "grounding_dino:requests"
RESULTS_CHANNEL = "grounding_dino:results"

# Visual Search uses a stub model by default. Flip GDINO_USE_STUB=0 once
# the real GroundingDINO weights + config are mounted into the container.
USE_STUB = os.environ.get("GDINO_USE_STUB", "1") != "0"


class GDinoService:
    def __init__(self):
        self.redis_url = os.environ.get("REDIS_URL", "redis://redis:6379/0")
        self.redis: Optional[redis.Redis] = None
        self._stop_event = threading.Event()
        self._thread: Optional[threading.Thread] = None

        # Lazy-loaded real model (None while not loaded). The stub does
        # not need any of this.
        self._model = None
        self._model_load_lock = threading.Lock()
        self._model_load_error: Optional[str] = None

    # ── lifecycle ─────────────────────────────────────────────────────────
    def start(self):
        if self._thread and self._thread.is_alive():
            return
        self._stop_event.clear()
        self._thread = threading.Thread(target=self._run_loop, daemon=True)
        self._thread.start()

    def stop(self):
        self._stop_event.set()
        if self._thread:
            self._thread.join(timeout=5)

    # ── main loop ─────────────────────────────────────────────────────────
    def _connect_redis(self):
        self.redis = redis.from_url(self.redis_url, decode_responses=True)
        self.redis.ping()

    def _run_loop(self):
        while not self._stop_event.is_set():
            try:
                if self.redis is None:
                    self._connect_redis()
                pubsub = self.redis.pubsub()
                pubsub.subscribe(REQUESTS_CHANNEL)
                print(f"[GDinoService] Subscribed to '{REQUESTS_CHANNEL}' (stub={USE_STUB})")

                for message in pubsub.listen():
                    if self._stop_event.is_set():
                        break
                    if message.get("type") != "message":
                        continue
                    try:
                        request = json.loads(message["data"])
                        self._handle_request(request)
                    except Exception as exc:
                        print(f"[GDinoService] Error handling request: {exc}")
            except (ConnectionError, TimeoutError) as exc:
                print(f"[GDinoService] Redis error: {exc}, reconnecting in 3s")
                self.redis = None
                time.sleep(3)
            except Exception as exc:
                print(f"[GDinoService] Unexpected loop error: {exc}")
                time.sleep(1)

    # ── request dispatch ──────────────────────────────────────────────────
    def _handle_request(self, request: dict):
        job_id = request.get("job_id")
        if job_id is None:
            return

        input_type = request.get("input_type")
        input_path = request.get("input_path")
        prompt = request.get("prompt", "")
        box_threshold = float(request.get("box_threshold", 0.35))
        text_threshold = float(request.get("text_threshold", 0.25))
        output_dir = Path(request.get("output_dir") or "/videos/gdino_outputs")
        output_dir.mkdir(parents=True, exist_ok=True)

        if not input_path or not Path(input_path).exists():
            self._publish_failure(job_id, f"Input file not found: {input_path}")
            return

        self._publish_status(job_id, "running")

        started = time.perf_counter()
        try:
            if input_type == "image":
                result = self._process_image(
                    job_id=job_id,
                    input_path=input_path,
                    prompt=prompt,
                    box_threshold=box_threshold,
                    text_threshold=text_threshold,
                    output_dir=output_dir,
                )
            elif input_type == "video":
                result = self._process_video(
                    job_id=job_id,
                    input_path=input_path,
                    prompt=prompt,
                    box_threshold=box_threshold,
                    text_threshold=text_threshold,
                    output_dir=output_dir,
                )
            else:
                self._publish_failure(job_id, f"Unknown input_type: {input_type}")
                return
        except Exception as exc:
            self._publish_failure(job_id, f"Inference failed: {exc}")
            return

        result["processing_ms"] = (time.perf_counter() - started) * 1000.0
        result["status"] = "completed"
        result["job_id"] = job_id
        self._publish(result)

    # ── image processing ──────────────────────────────────────────────────
    def _process_image(
        self,
        job_id: int,
        input_path: str,
        prompt: str,
        box_threshold: float,
        text_threshold: float,
        output_dir: Path,
    ) -> dict:
        image = cv2.imread(input_path)
        if image is None:
            raise RuntimeError("Could not read image (invalid file or unsupported codec)")

        h, w = image.shape[:2]

        if USE_STUB or not self._ensure_model():
            detections = self._stub_detections(prompt, w, h)
        else:
            detections = self._real_image_inference(
                image, prompt, box_threshold, text_threshold
            )

        annotated = self._draw_detections(image.copy(), detections)
        out_path = output_dir / f"job_{job_id}_{uuid.uuid4().hex[:8]}.jpg"
        cv2.imwrite(str(out_path), annotated, [cv2.IMWRITE_JPEG_QUALITY, 88])

        return {
            "detections": detections,
            "summary": self._summarize(detections),
            "output_image_path": str(out_path),
        }

    # ── video processing (sampled frames) ─────────────────────────────────
    def _process_video(
        self,
        job_id: int,
        input_path: str,
        prompt: str,
        box_threshold: float,
        text_threshold: float,
        output_dir: Path,
    ) -> dict:
        """Sample N evenly-spaced frames, run detection on each, write an
        annotated mp4. Sampling keeps total inference time bounded even
        for long uploads."""
        cap = cv2.VideoCapture(input_path)
        if not cap.isOpened():
            raise RuntimeError("Could not open video")

        total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
        fps = float(cap.get(cv2.CAP_PROP_FPS) or 25.0)
        width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH) or 0)
        height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT) or 0)

        # Sample up to 60 frames so even long videos finish reasonably fast.
        # Tune in one place; downstream UI just consumes the annotated output.
        sample_count = min(60, max(1, total_frames))
        sample_indices = (
            np.linspace(0, max(0, total_frames - 1), sample_count).astype(int).tolist()
            if total_frames > 0
            else [0]
        )

        out_path = output_dir / f"job_{job_id}_{uuid.uuid4().hex[:8]}.mp4"
        # mp4v is what the rest of the system uses (see pipeline_manager).
        writer = cv2.VideoWriter(
            str(out_path),
            cv2.VideoWriter_fourcc(*"mp4v"),
            max(1.0, min(fps, 25.0)),
            (width or 640, height or 480),
        )
        if not writer.isOpened():
            cap.release()
            raise RuntimeError("Could not open video writer for output")

        per_frame: list[dict] = []
        for idx in sample_indices:
            cap.set(cv2.CAP_PROP_POS_FRAMES, int(idx))
            ok, frame = cap.read()
            if not ok or frame is None:
                continue

            if USE_STUB or not self._ensure_model():
                detections = self._stub_detections(prompt, frame.shape[1], frame.shape[0])
            else:
                detections = self._real_image_inference(
                    frame, prompt, box_threshold, text_threshold
                )

            per_frame.append({"frame_index": int(idx), "detections": detections})
            annotated = self._draw_detections(frame.copy(), detections)
            writer.write(annotated)

        writer.release()
        cap.release()

        # Flatten for the summary card (treat the whole video as one bag of
        # detections — the per-frame structure is still in `summary.per_frame`).
        flat: list[dict] = []
        for entry in per_frame:
            flat.extend(entry["detections"])

        summary = self._summarize(flat)
        summary["sampled_frames"] = len(per_frame)
        summary["total_frames"] = total_frames
        summary["per_frame"] = per_frame[:20]  # cap to avoid bloating the row

        return {
            "detections": flat,
            "summary": summary,
            "output_video_path": str(out_path),
        }

    # ── inference backends ────────────────────────────────────────────────
    def _ensure_model(self) -> bool:
        """Lazy-load the real GroundingDINO model. Returns True on success.

        Stays a no-op while USE_STUB is true so we never pay the import cost
        for users who never touch Visual Search.
        """
        if USE_STUB:
            return False
        if self._model is not None:
            return True
        if self._model_load_error is not None:
            return False

        with self._model_load_lock:
            if self._model is not None:
                return True
            if self._model_load_error is not None:
                return False
            try:
                # The real loader is implemented in a separate module so this
                # file stays importable even when GroundingDINO isn't
                # installed. See manager/gdino_loader.py (added in the
                # "wire real GroundingDINO" task).
                from manager.gdino_loader import load_gdino_model

                self._model = load_gdino_model()
                print("[GDinoService] Real GroundingDINO model loaded")
                return True
            except Exception as exc:
                self._model_load_error = f"GroundingDINO load failed: {exc}"
                print(f"[GDinoService] {self._model_load_error}")
                return False

    def _real_image_inference(
        self,
        bgr_image: np.ndarray,
        prompt: str,
        box_threshold: float,
        text_threshold: float,
    ) -> list[dict]:
        """Real inference path. Only reached when USE_STUB is False and the
        model loaded successfully."""
        from manager.gdino_loader import run_gdino_inference

        return run_gdino_inference(
            model=self._model,
            bgr_image=bgr_image,
            prompt=prompt,
            box_threshold=box_threshold,
            text_threshold=text_threshold,
        )

    def _stub_detections(self, prompt: str, w: int, h: int) -> list[dict]:
        """Deterministic fake detections so the UI is testable without the
        real model. Picks one centered box per prompt phrase."""
        phrases = [p.strip() for p in prompt.replace(",", ".").split(".") if p.strip()]
        if not phrases:
            phrases = ["object"]

        detections = []
        # Spread the boxes across the frame horizontally so the annotated
        # output actually looks like multi-object detection.
        for i, phrase in enumerate(phrases[:5]):
            slot = (i + 0.5) / max(1, min(len(phrases), 5))
            cx = int(w * slot)
            cy = int(h * 0.5)
            bw = int(w * 0.18)
            bh = int(h * 0.45)
            x1 = max(0, cx - bw // 2)
            y1 = max(0, cy - bh // 2)
            x2 = min(w, cx + bw // 2)
            y2 = min(h, cy + bh // 2)
            # Fake confidence that's stable per phrase
            conf = round(0.65 + (hash(phrase) % 30) / 100.0, 2)
            detections.append({
                "label": phrase,
                "confidence": conf,
                "box": [x1, y1, x2, y2],
            })
        return detections

    # ── annotation + summary ──────────────────────────────────────────────
    def _draw_detections(self, image: np.ndarray, detections: list[dict]) -> np.ndarray:
        for det in detections:
            x1, y1, x2, y2 = (int(v) for v in det["box"])
            label = f"{det['label']} {det['confidence']:.2f}"
            color = self._color_for_label(det["label"])
            cv2.rectangle(image, (x1, y1), (x2, y2), color, 2)
            (tw, th), _ = cv2.getTextSize(label, cv2.FONT_HERSHEY_SIMPLEX, 0.55, 1)
            cv2.rectangle(image, (x1, y1 - th - 8), (x1 + tw + 6, y1), color, -1)
            cv2.putText(
                image, label, (x1 + 3, y1 - 5),
                cv2.FONT_HERSHEY_SIMPLEX, 0.55, (255, 255, 255), 1, cv2.LINE_AA,
            )
        return image

    def _color_for_label(self, label: str) -> tuple[int, int, int]:
        # Deterministic but reasonably-spread colors per label string.
        h = abs(hash(label))
        return (60 + h % 180, 80 + (h // 180) % 160, 90 + (h // (180 * 160)) % 160)

    def _summarize(self, detections: list[dict]) -> dict:
        counts: dict[str, int] = {}
        for det in detections:
            counts[det["label"]] = counts.get(det["label"], 0) + 1
        return {
            "total_detections": len(detections),
            "counts": counts,
        }

    # ── publishing ────────────────────────────────────────────────────────
    def _publish(self, payload: dict):
        try:
            self.redis.publish(RESULTS_CHANNEL, json.dumps(payload))
        except Exception as exc:
            print(f"[GDinoService] publish failed: {exc}")

    def _publish_status(self, job_id: int, status: str):
        self._publish({"job_id": job_id, "status": status})

    def _publish_failure(self, job_id: int, error: str):
        self._publish({
            "job_id": job_id,
            "status": "failed",
            "error": error,
            "detections": [],
            "summary": {},
        })

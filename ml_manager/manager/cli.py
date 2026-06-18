#!/usr/bin/env python3
"""
Standalone CLI for fall and seizure detection.

Runs detection directly on a video file, webcam, or RTSP stream without
requiring the Redis pub/sub pipeline or Docker. Useful for model evaluation
and debugging.

Usage:
  python manager/cli.py --model-type fall    --source path/to/video.mp4
  python manager/cli.py --model-type seizure --source path/to/video.mp4
  python manager/cli.py --model-type fall    --source 0          # webcam index
  python manager/cli.py --model-type seizure --source rtsp://... --output out.mp4

All paths are relative to the ml_manager/ directory (parent of this file).
"""

import argparse
import json
import sys
import time
import warnings
from collections import deque
from pathlib import Path

import cv2
import numpy as np
import torch

# ─── Path setup ───────────────────────────────────────────────────────────────
# Allow imports from ml_manager/ without installing the package.
_BASE_DIR = Path(__file__).resolve().parent.parent   # → ml_manager/
sys.path.insert(0, str(_BASE_DIR))

# ─── Shared preprocessing modules ─────────────────────────────────────────────
from steps.pose_detection.pose_detection import (
    RTMPoseDetector,
    IntelligentPoseTracker,
    detect_pose_with_intelligent_tracking,
)
from steps.patch_extraction.enhanced_extract_patches import (
    extract_patches_with_confidence,
    FALL_INDICES,
    SEIZURE_INDICES,
)
from steps.kinematics.kinematic_features import KinematicFeatureExtractor

# ─── Constants ────────────────────────────────────────────────────────────────
WINDOW = 30
STRIDE = 15
SMOOTH_WINDOW = 5


# ─── Helpers ──────────────────────────────────────────────────────────────────

def _load_source(source: str):
    """Open a video source. Returns cv2.VideoCapture."""
    try:
        idx = int(source)
        cap = cv2.VideoCapture(idx)
    except ValueError:
        cap = cv2.VideoCapture(source)
    if not cap.isOpened():
        raise RuntimeError(f"Cannot open source: {source}")
    return cap


def _load_checkpoint(path: Path):
    """Load a PyTorch checkpoint safely."""
    try:
        return torch.load(path, map_location="cpu", weights_only=True)
    except Exception:
        warnings.warn(
            f"[CLI] Loading {path.name} with weights_only=False — ensure the "
            "checkpoint is from a trusted source."
        )
        return torch.load(path, map_location="cpu", weights_only=False)


def _patches_hwc_to_chw(patches_np: np.ndarray) -> torch.Tensor:
    return torch.from_numpy(patches_np).permute(0, 3, 1, 2).float()


def _normalize_keypoints_seizure(kpts15_window: list) -> torch.Tensor:
    """
    Center + RMS normalization for seizure model keypoints.
    kpts15_window: list of T arrays, each (15, 3).
    Returns (1, T, 15, 3) tensor on CPU.
    """
    kpts = torch.stack([torch.tensor(k, dtype=torch.float32) for k in kpts15_window])
    _xy, _c = kpts[..., :2], kpts[..., 2:3]
    _m = (_c > 0.1).float()
    _n = _m.sum().clamp(min=1.0)
    _center = (_xy * _m).sum(dim=(0, 1)) / _n
    _centered = _xy - _center
    _scale = ((_centered * _m).pow(2).sum() / _n).sqrt().clamp(min=1e-3)
    normalized = torch.cat([_centered / _scale, _c], dim=-1)
    return normalized.unsqueeze(0)


def _draw_overlay(frame, label: str, prob: float, is_event: bool, fps: float,
                  buf_len: int):
    """Draw status overlay on frame."""
    h, w = frame.shape[:2]
    color = (0, 0, 220) if is_event else (0, 180, 0)
    cv2.rectangle(frame, (0, 0), (w, 50), (0, 0, 0), -1)
    cv2.putText(frame, f"{label}  p={prob:.3f}", (10, 35),
                cv2.FONT_HERSHEY_SIMPLEX, 0.9, color, 2)
    cv2.putText(frame, f"FPS:{fps:.1f}  buf:{buf_len}/{WINDOW}",
                (w - 200, 35), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (180, 180, 180), 1)
    return frame


# ─── Fall detection runner ────────────────────────────────────────────────────

def run_fall_detection(source: str, output: str | None, threshold: float,
                       device: str, display: bool, max_frames: int | None):
    """Run fall detection on a video source."""
    print(f"\n[CLI] Fall detection  source={source}  threshold={threshold}")

    dev = torch.device(device if torch.cuda.is_available() else "cpu")
    model_path = _BASE_DIR / "models" / "VSViGFall.pth"
    if not model_path.exists():
        raise FileNotFoundError(f"Model not found: {model_path}")

    ckpt = _load_checkpoint(model_path)
    use_global = True
    use_kinematic = True
    if isinstance(ckpt, dict) and "model_state_dict" in ckpt:
        use_global = ckpt.get("use_global_patches", use_global)
        use_kinematic = ckpt.get("use_kinematic_features", use_kinematic)
        state_dict = ckpt["model_state_dict"]
    else:
        state_dict = ckpt

    from steps.fall_detection.VSViG_enhanced import EnhancedVSViG_base
    from steps.global_patch_extraction.global_patch_extractor import extract_global_patch

    model = EnhancedVSViG_base(use_global_patches=use_global,
                                use_kinematic_features=use_kinematic)
    model.load_state_dict(state_dict)
    model.to(dev).eval()
    print(f"   Model loaded  global={use_global}  kinematic={use_kinematic}")

    rtm = RTMPoseDetector(provider='cuda' if dev.type == 'cuda' else 'cpu')
    tracker = IntelligentPoseTracker()
    kin_extractor = KinematicFeatureExtractor()

    kpts18_buf: deque = deque(maxlen=WINDOW)
    patches_buf: deque = deque(maxlen=WINDOW)
    global_buf: deque = deque(maxlen=WINDOW)
    kin_buf: deque = deque(maxlen=WINDOW)
    prev_bbox = None

    cap = _load_source(source)
    fps_src = cap.get(cv2.CAP_PROP_FPS) or 30.0
    writer = None
    if output:
        fourcc = cv2.VideoWriter_fourcc(*"mp4v")
        w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        writer = cv2.VideoWriter(output, fourcc, fps_src, (w, h))

    frame_idx = 0
    history: deque = deque(maxlen=SMOOTH_WINDOW)
    last_prob = 0.0
    last_label = "Buffering…"
    t_loop = time.perf_counter()
    fps_disp = 0.0

    print("[CLI] Processing… (press q to quit)")
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        frame_idx += 1
        if max_frames and frame_idx > max_frames:
            break

        kpts_xy, confs = detect_pose_with_intelligent_tracking(
            rtm, frame, tracker, confidence_threshold=0.25, preprocess=True
        )
        kpts18_3d = np.concatenate(
            [kpts_xy, confs[:, np.newaxis]], axis=1
        ).astype(np.float32)

        patches, _, _ = extract_patches_with_confidence(
            frame, kpts18_3d, indices_to_keep=FALL_INDICES, ref_height=1080
        )

        gp, bbox_info = extract_global_patch(frame, kpts18_3d, prev_bbox=prev_bbox)
        prev_bbox = bbox_info.get("smoothed_bbox")

        kpts18_buf.append(kpts18_3d)
        patches_buf.append(patches)
        global_buf.append(gp)

        # Kinematic features (need 18-pt sequence)
        if len(kpts18_buf) >= 2:
            seq = np.stack(list(kpts18_buf), axis=0)
            kin_vec = kin_extractor.create_feature_vector(
                kin_extractor.extract_all_features(seq)
            )
        else:
            kin_vec = np.zeros(25, dtype=np.float32)
        kin_buf.append(kin_vec)

        if len(kpts18_buf) == WINDOW and frame_idx % STRIDE == 0:
            from manager.workers.fall_detection_worker import (
                OPENPOSE_18_TO_VSVIG_15, _patches_hwc_to_chw, _kpts18_to_15,
            )
            kl = list(kpts18_buf)
            pl = list(patches_buf)
            pt = torch.stack([_patches_hwc_to_chw(p) for p in pl]).unsqueeze(0).to(dev)
            kt = torch.from_numpy(
                np.stack([_kpts18_to_15(k) for k in kl])
            ).float().unsqueeze(0).to(dev)

            gp_t = None
            if use_global:
                gp_t = torch.from_numpy(
                    np.stack(list(global_buf))
                ).float().unsqueeze(0).to(dev)

            kf_t = None
            if use_kinematic:
                kf_t = torch.from_numpy(list(kin_buf)[-1]).float().unsqueeze(0).to(dev)

            with torch.no_grad():
                out = model(local_patches=pt, keypoints=kt,
                            global_patches=gp_t, kinematic_features=kf_t,
                            return_logits=True)
                logits = out[0] if isinstance(out, tuple) else out
                prob = torch.sigmoid(logits).squeeze().item()

            history.append(prob)
            last_prob = float(np.mean(list(history)))
            is_fall = last_prob >= threshold
            if is_fall:
                last_label = "FALL DETECTED"
                print(json.dumps({"frame": frame_idx, "event": "fall",
                                  "probability": round(last_prob, 4)}))
            else:
                last_label = "Normal"

        # FPS
        now = time.perf_counter()
        fps_disp = 0.9 * fps_disp + 0.1 * (1.0 / max(now - t_loop, 1e-6))
        t_loop = now

        _draw_overlay(frame, last_label, last_prob, last_prob >= threshold,
                      fps_disp, len(kpts18_buf))
        if writer:
            writer.write(frame)
        if display:
            cv2.imshow("Fall Detection CLI", frame)
            if cv2.waitKey(1) & 0xFF == ord('q'):
                break

    cap.release()
    if writer:
        writer.release()
    cv2.destroyAllWindows()
    print(f"\n[CLI] Done. Processed {frame_idx} frames.")


# ─── Seizure detection runner ─────────────────────────────────────────────────

def run_seizure_detection(source: str, output: str | None, threshold: float,
                          device: str, display: bool, max_frames: int | None):
    """Run seizure detection on a video source."""
    print(f"\n[CLI] Seizure detection  source={source}  threshold={threshold}")

    dev = torch.device(device if torch.cuda.is_available() else "cpu")
    model_path = _BASE_DIR / "models" / "SeizureVSViG_winner_nogkn.pth"
    if not model_path.exists():
        raise FileNotFoundError(f"Model not found: {model_path}")

    ckpt = _load_checkpoint(model_path)
    state_dict = ckpt["model_state_dict"] if isinstance(ckpt, dict) and "model_state_dict" in ckpt else ckpt

    from steps.seizure_detection.VSViG_enhanced import EnhancedVSViG_base

    model = EnhancedVSViG_base(use_global_patches=False, use_kinematic_features=True)
    model.load_state_dict(state_dict, strict=True)
    model.to(dev).eval()
    print(f"   Model loaded  global=False  kinematic=True")

    rtm = RTMPoseDetector(provider='cuda' if dev.type == 'cuda' else 'cpu')
    tracker = IntelligentPoseTracker()
    kin_extractor = KinematicFeatureExtractor()

    kpts18_buf: deque = deque(maxlen=WINDOW)
    kpts15_buf: deque = deque(maxlen=WINDOW)
    patches_buf: deque = deque(maxlen=WINDOW)
    kin_buf: deque = deque(maxlen=WINDOW)

    cap = _load_source(source)
    fps_src = cap.get(cv2.CAP_PROP_FPS) or 30.0
    writer = None
    if output:
        fourcc = cv2.VideoWriter_fourcc(*"mp4v")
        w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        writer = cv2.VideoWriter(output, fourcc, fps_src, (w, h))

    frame_idx = 0
    history: deque = deque(maxlen=SMOOTH_WINDOW)
    last_prob = 0.0
    last_label = "Buffering…"
    t_loop = time.perf_counter()
    fps_disp = 0.0

    print("[CLI] Processing… (press q to quit)")
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        frame_idx += 1
        if max_frames and frame_idx > max_frames:
            break

        kpts_xy, confs = detect_pose_with_intelligent_tracking(
            rtm, frame, tracker, confidence_threshold=0.25, preprocess=True
        )
        kpts18_3d = np.concatenate(
            [kpts_xy, confs[:, np.newaxis]], axis=1
        ).astype(np.float32)

        patches, _, _ = extract_patches_with_confidence(
            frame, kpts18_3d, indices_to_keep=SEIZURE_INDICES, ref_height=1080
        )

        kpts18_buf.append(kpts18_3d)
        kpts15_buf.append(kpts18_3d[SEIZURE_INDICES])
        patches_buf.append(patches)

        if len(kpts18_buf) >= 2:
            seq = np.stack(list(kpts18_buf), axis=0)
            kin_vec = kin_extractor.create_feature_vector(
                kin_extractor.extract_all_features(seq)
            )
        else:
            kin_vec = np.zeros(25, dtype=np.float32)
        kin_buf.append(kin_vec)

        if len(kpts15_buf) == WINDOW and frame_idx % STRIDE == 0:
            kpts_t = _normalize_keypoints_seizure(list(kpts15_buf)).to(dev)

            pt = torch.stack(
                [_patches_hwc_to_chw(p) for p in patches_buf]
            ).unsqueeze(0).to(dev)

            kf_t = torch.from_numpy(list(kin_buf)[-1]).float().unsqueeze(0).to(dev)

            with torch.no_grad():
                out = model(local_patches=pt, keypoints=kpts_t,
                            global_patches=None, kinematic_features=kf_t,
                            return_logits=True)
                logits = out[0] if isinstance(out, tuple) else out
                prob = torch.sigmoid(logits).squeeze().item()

            history.append(prob)
            last_prob = float(np.mean(list(history)))
            is_seizure = last_prob >= threshold
            if is_seizure:
                last_label = "SEIZURE DETECTED"
                print(json.dumps({"frame": frame_idx, "event": "seizure",
                                  "probability": round(last_prob, 4)}))
            else:
                last_label = "Normal"

        # FPS
        now = time.perf_counter()
        fps_disp = 0.9 * fps_disp + 0.1 * (1.0 / max(now - t_loop, 1e-6))
        t_loop = now

        _draw_overlay(frame, last_label, last_prob, last_prob >= threshold,
                      fps_disp, len(kpts15_buf))
        if writer:
            writer.write(frame)
        if display:
            cv2.imshow("Seizure Detection CLI", frame)
            if cv2.waitKey(1) & 0xFF == ord('q'):
                break

    cap.release()
    if writer:
        writer.release()
    cv2.destroyAllWindows()
    print(f"\n[CLI] Done. Processed {frame_idx} frames.")


# ─── Entry point ──────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Standalone fall/seizure detection CLI"
    )
    parser.add_argument(
        "--model-type", choices=["fall", "seizure"], required=True,
        help="Detection model to run"
    )
    parser.add_argument(
        "--source", required=True,
        help="Video file path, webcam index (0, 1, …), or RTSP URL"
    )
    parser.add_argument(
        "--output", default=None,
        help="Optional: save annotated output video to this path"
    )
    parser.add_argument(
        "--threshold", type=float, default=0.5,
        help="Detection probability threshold (default: 0.5)"
    )
    parser.add_argument(
        "--device", default="cuda",
        help="PyTorch device: cuda or cpu (default: cuda, falls back to cpu)"
    )
    parser.add_argument(
        "--no-display", action="store_true",
        help="Disable real-time video display (useful in headless environments)"
    )
    parser.add_argument(
        "--max-frames", type=int, default=None,
        help="Stop after this many frames (for quick tests)"
    )
    args = parser.parse_args()

    display = not args.no_display

    if args.model_type == "fall":
        run_fall_detection(
            source=args.source,
            output=args.output,
            threshold=args.threshold,
            device=args.device,
            display=display,
            max_frames=args.max_frames,
        )
    else:
        run_seizure_detection(
            source=args.source,
            output=args.output,
            threshold=args.threshold,
            device=args.device,
            display=display,
            max_frames=args.max_frames,
        )


if __name__ == "__main__":
    main()

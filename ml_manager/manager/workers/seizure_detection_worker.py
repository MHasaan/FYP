"""
Seizure Detection Worker — Sliding-window seizure detection inference.

Uses the SeizureVSViG_winner_nogkn.pth checkpoint (EnhancedVSViG_base with
use_global_patches=False). The winner model was trained WITHOUT global patches
because the ResNet18 body-crop encoder learned patient appearance rather than
seizure dynamics, collapsing held-out AUROC from 0.84 to 0.63.

Key differences from FallDetectionWorker:
  - Receives patches_seizure from the shared patch_extraction_seizure DAG step
    (SEIZURE_INDICES ordering). No internal patch extraction.
  - Applies center + RMS-scale keypoint normalization before inference
    (critical for generalizing to new patients)
  - global_patches is always None — disabled at architecture level
  - DAG dependencies: pose + kinematics + patch_extraction_seizure

Depends on: pose worker, kinematics worker, patch_extraction_seizure worker
"""

import warnings
import numpy as np
import torch
from collections import deque
from pathlib import Path
from typing import Any, Optional

from manager.workers.base_worker import BaseWorker

# ─── Constants ────────────────────────────────────────────────────────────────

WINDOW = 30   # frames per inference window (~1 sec at 30 FPS)
STRIDE = 15   # run inference every STRIDE frames (50% overlap)

# SeizureVSViG_winner_nogkn.pth keypoint ordering (18 → 15 OpenPose indices).
# Drops: neck(1), left_eye(15), right_ear(16). Natural index order.
SEIZURE_INDICES = [0, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 17]

# Smoothing window for temporal detection history
SMOOTH_WINDOW = 5

# Skeleton edges for optional visualisation (OpenPose 18-pt)
SKELETON_EDGES = [
    (0, 1), (1, 2), (2, 3), (3, 4),
    (1, 5), (5, 6), (6, 7),
    (1, 8), (8, 9), (9, 10),
    (1, 11), (11, 12), (12, 13),
    (0, 14), (0, 15), (14, 16), (15, 17),
]


def _patches_hwc_to_chw(patches_np: np.ndarray) -> torch.Tensor:
    """Convert (15, H, W, 3) uint8 HWC → float32 (15, 3, H, W) tensor."""
    return torch.from_numpy(patches_np).permute(0, 3, 1, 2).float()


class SeizureDetectionWorker(BaseWorker):
    """
    Sliding-window seizure detection inference worker.

    Self-contained: performs its own patch extraction with the seizure-specific
    keypoint ordering (SEIZURE_INDICES). Does NOT depend on the shared
    patch_extraction DAG step (which uses FALL_INDICES for the fall model).

    Input keys from pipeline: frame, pose, kinematic_features, kinematic_ready
    Output: {"seizure_detection": {probability, is_seizure, label, ...}}
    """

    def __init__(self, model_path: Optional[str] = None,
                 model_type: str = 'base'):
        super().__init__(name="seizure_detection", model_path=model_path)
        self._model = None
        self._model_type = model_type
        self._device = None

        # Temporal buffers (most-recent WINDOW entries)
        self._kpts15_buf: deque = deque(maxlen=WINDOW)
        self._patches_buf: deque = deque(maxlen=WINDOW)
        self._kinematic_buf: deque = deque(maxlen=WINDOW)
        self._detection_history: deque = deque(maxlen=SMOOTH_WINDOW)

        # Inference state
        self._frame_count = 0
        self._last_prob = 0.0
        self._last_label = "Initialising…"
        self._inference_count = 0
        self._seizure_detections = 0
        self._inference_times: deque = deque(maxlen=30)

        # Detection threshold
        self._threshold = 0.5
        self._alert_threshold = 0.75

    # ─── Model lifecycle ──────────────────────────────────────────────────────

    def load_model(self):
        """Load the SeizureVSViG model."""
        import torch

        self._device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')

        # Resolve model path
        if self.model_path is None:
            base_dir = Path(__file__).resolve().parent.parent.parent
            self.model_path = str(
                base_dir / "models" / "SeizureVSViG_winner_nogkn.pth"
            )

        model_path = Path(self.model_path)
        if not model_path.exists():
            print(f"❌ Seizure detection model not found: {model_path}")
            self.is_loaded = False
            return

        print(f"🧠 Loading seizure detection model from: {model_path}")
        print(f"   Device: {self._device}")

        try:
            # Load model weights — try safe mode first
            try:
                checkpoint = torch.load(
                    model_path, map_location='cpu', weights_only=True
                )
            except Exception:
                print(
                    "[SeizureWorker] WARNING: loading with weights_only=False "
                    "— ensure checkpoint is from a trusted source"
                )
                checkpoint = torch.load(
                    model_path, map_location='cpu', weights_only=False
                )

            # Build architecture (global patches always disabled for winner)
            from steps.seizure_detection.VSViG_enhanced import (
                EnhancedVSViG_base, EnhancedVSViG_light,
            )
            factory = (EnhancedVSViG_base if self._model_type == 'base'
                       else EnhancedVSViG_light)
            self._model = factory(
                use_global_patches=False,
                use_kinematic_features=True,
            )

            # Load state dict (handle both full checkpoint and bare state_dict)
            if isinstance(checkpoint, dict) and 'model_state_dict' in checkpoint:
                state_dict = checkpoint['model_state_dict']
                epoch = checkpoint.get('epoch', '?')
                print(f"   Checkpoint epoch: {epoch}")
            else:
                state_dict = checkpoint

            self._model.load_state_dict(state_dict, strict=True)
            self._model.to(self._device).eval()

            n_params = sum(p.numel() for p in self._model.parameters())
            print(f"✅ Seizure detection model loaded")
            print(f"   Parameters: {n_params:,}")
            print(f"   Global patches: False (disabled for winner model)")
            print(f"   Kinematic features: True")
            print(f"   Threshold: {self._threshold}")

            self.is_loaded = True

        except Exception as e:
            print(f"❌ Failed to load seizure detection model: {e}")
            import traceback
            traceback.print_exc()
            self.is_loaded = False

    def unload_model(self):
        """Release model and GPU resources."""
        if self._model is not None:
            del self._model
            self._model = None
        self._device = None
        self.reset_state()
        self.is_loaded = False
        try:
            if torch.cuda.is_available():
                torch.cuda.empty_cache()
        except Exception:
            pass
        print(f"🧠 Seizure detection model unloaded")

    # ─── Per-frame processing ─────────────────────────────────────────────────

    def process(self, inputs: dict[str, Any]) -> dict[str, Any]:
        """
        Buffer per-frame data and run sliding-window seizure detection.

        Args:
            inputs: {
                "frame": np.ndarray (H, W, 3) — BGR frame,
                "pose": dict with keypoints_3d (18, 3),
                "kinematic_features": np.ndarray (25,),
                "kinematic_ready": bool,
                "patches_seizure": np.ndarray (15, 32, 32, 3) — from patch_extraction_seizure step,
            }

        Returns:
            {"seizure_detection": {probability, is_seizure, label, ...}}
        """
        self._frame_count += 1

        # ── Extract inputs ────────────────────────────────────────────────
        pose_data = inputs.get("pose", {})

        kpts18_3d = np.zeros((18, 3), dtype=np.float32)
        if isinstance(pose_data, dict) and "keypoints_3d" in pose_data:
            k = np.array(pose_data["keypoints_3d"], dtype=np.float32)
            if k.shape == (18, 3):
                kpts18_3d = k

        kin_features = inputs.get("kinematic_features", None)
        if kin_features is None:
            kin_features = np.zeros(25, dtype=np.float32)
        kin_features = np.array(kin_features, dtype=np.float32)
        if kin_features.shape != (25,):
            kin_features = np.zeros(25, dtype=np.float32)

        kinematic_ready = bool(inputs.get("kinematic_ready", False))

        # ── Receive patches from shared patch_extraction_seizure DAG step ──
        patches = inputs.get("patches_seizure")
        if patches is None:
            patches = np.zeros((15, 32, 32, 3), dtype=np.uint8)

        # ── Buffer update ─────────────────────────────────────────────────
        kpts15 = kpts18_3d[SEIZURE_INDICES]  # (15, 3)
        self._kpts15_buf.append(kpts15)
        self._patches_buf.append(patches)
        self._kinematic_buf.append(kin_features)

        # ── Inference when buffer full + stride condition ─────────────────
        if (len(self._kpts15_buf) == WINDOW
                and kinematic_ready
                and self._frame_count % STRIDE == 0):
            self._run_inference()

        # ── Build result ──────────────────────────────────────────────────
        is_seizure = self._last_prob >= self._threshold
        avg_inf = (sum(self._inference_times) / len(self._inference_times)
                   if self._inference_times else 0.0)

        return {
            "seizure_detection": {
                "probability": round(self._last_prob, 4),
                "is_seizure": is_seizure,
                "label": self._last_label,
                "inference_count": self._inference_count,
                "seizure_detections": self._seizure_detections,
                "frame_count": self._frame_count,
                "avg_inference_time_ms": round(avg_inf * 1000, 1),
                "threshold": self._threshold,
                "alert_threshold": self._alert_threshold,
                "skeleton_edges": SKELETON_EDGES,
            }
        }

    # ─── Inference ────────────────────────────────────────────────────────────

    def _run_inference(self):
        """Run model inference on the current sliding window."""
        import time
        t0 = time.time()

        try:
            # ── Build keypoint tensor with normalization ───────────────────
            kpts_tensor = self._normalize_keypoints()   # (1, 30, 15, 3)

            # ── Build patches tensor ──────────────────────────────────────
            patches_t = torch.stack(
                [_patches_hwc_to_chw(p) for p in self._patches_buf]
            )  # (30, 15, 3, 32, 32)
            patches_t = patches_t.unsqueeze(0).to(self._device)  # (1, 30, 15, 3, 32, 32)

            # ── Build kinematic features tensor ───────────────────────────
            kin_arr = list(self._kinematic_buf)[-1]
            kin_t = torch.from_numpy(kin_arr).float().unsqueeze(0).to(self._device)  # (1, 25)

            # ── Model forward — global_patches=None (always disabled) ─────
            with torch.no_grad():
                out = self._model(
                    local_patches=patches_t,
                    keypoints=kpts_tensor,
                    global_patches=None,
                    kinematic_features=kin_t,
                    return_logits=True,
                )
                logits = out[0] if isinstance(out, tuple) else out
                prob = torch.sigmoid(logits).squeeze().item()

            # ── Temporal smoothing ────────────────────────────────────────
            self._detection_history.append(prob)
            smoothed = float(np.mean(list(self._detection_history)))

            # ── State update ──────────────────────────────────────────────
            self._last_prob = smoothed
            self._inference_count += 1
            elapsed = time.time() - t0
            self._inference_times.append(elapsed)

            is_seizure = smoothed >= self._threshold
            if is_seizure:
                self._seizure_detections += 1
                print(f"⚠️ [SeizureWorker] SEIZURE DETECTED! Prob: {smoothed:.4f}")
            elif smoothed > 0.1:
                print(f"ℹ️ [SeizureWorker] Inference: prob={smoothed:.4f}")

            if smoothed >= self._alert_threshold:
                self._last_label = "⚠ SEIZURE DETECTED"
            elif smoothed >= self._threshold:
                self._last_label = "SEIZURE"
            elif smoothed >= self._threshold * 0.7:
                self._last_label = "Caution"
            else:
                self._last_label = "Normal"

        except Exception as e:
            warnings.warn(f"[SeizureDetection] Inference error: {e}")
            import traceback
            traceback.print_exc()

    def _normalize_keypoints(self) -> torch.Tensor:
        """
        Build the (1, T, 15, 3) keypoint tensor with center + RMS normalization.

        Normalization removes absolute position and apparent body size (camera
        distance / subject scale) so the model focuses on shape and dynamics.
        This is the key factor behind the model's generalization to new patients.
        """
        kpts = torch.stack(
            [torch.tensor(k, dtype=torch.float32) for k in self._kpts15_buf]
        )  # (30, 15, 3)

        _xy = kpts[..., :2]     # (30, 15, 2)
        _c  = kpts[..., 2:3]    # (30, 15, 1)

        # Mask confident keypoints
        _m = (_c > 0.1).float()
        _n = _m.sum().clamp(min=1.0)

        # Center on centroid of confident keypoints
        _center = (_xy * _m).sum(dim=(0, 1)) / _n
        _centered = _xy - _center

        # Scale by RMS spread of confident keypoints
        _scale = ((_centered * _m).pow(2).sum() / _n).sqrt().clamp(min=1e-3)

        normalized = torch.cat([_centered / _scale, _c], dim=-1)  # (30, 15, 3)
        return normalized.unsqueeze(0).to(self._device)            # (1, 30, 15, 3)

    # ─── Config & state ───────────────────────────────────────────────────────

    def reset_state(self):
        """Reset all internal buffers and counters."""
        self._kpts15_buf.clear()
        self._patches_buf.clear()
        self._kinematic_buf.clear()
        self._detection_history.clear()
        self._frame_count = 0
        self._last_prob = 0.0
        self._last_label = "Initialising…"
        self._inference_count = 0
        self._seizure_detections = 0
        self._inference_times.clear()

    def update_config(self, config: dict[str, Any]):
        """Update seizure detection configuration at runtime.

        Supported keys:
            - threshold (float): Detection threshold 0-1 (default: 0.5)
            - alert_threshold (float): High-confidence threshold (default: 0.75)
        """
        if "threshold" in config:
            self._threshold = float(config["threshold"])
        if "alert_threshold" in config:
            self._alert_threshold = float(config["alert_threshold"])
        print(f"[SeizureDetection] Config updated: threshold={self._threshold}, "
              f"alert_threshold={self._alert_threshold}")

    def get_config(self) -> dict[str, Any]:
        """Return current configuration."""
        return {
            "threshold": self._threshold,
            "alert_threshold": self._alert_threshold,
            "model_type": self._model_type,
            "use_global_patches": False,
            "use_kinematic_features": True,
            "window_size": WINDOW,
            "stride": STRIDE,
            "device": str(self._device) if self._device else "unknown",
        }

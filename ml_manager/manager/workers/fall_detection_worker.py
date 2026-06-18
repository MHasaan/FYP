"""
Fall Detection Worker — Sliding-window fall detection inference.

Wraps the full EnhancedVSViG inference pipeline from detect_fall_production.py:
  - Accumulates 30-frame sliding windows of all modalities
  - Runs model inference every STRIDE (15) frames
  - Converts per-frame outputs to model-compatible tensor formats
  - Returns fall probability, label, and inference statistics

This worker acts as the final aggregator: it consumes outputs from
pose_worker, patch_extraction_worker, global_patch_worker, and
kinematics_worker, buffers them temporally, and runs the trained model.

Depends on: pose, patch_extraction, global_patch, kinematics workers
"""

import warnings
import numpy as np
import torch
import torch.nn.functional as F
from collections import deque
from pathlib import Path
from typing import Any, Optional
from manager.workers.base_worker import BaseWorker


# ─── Constants matching detect_fall_production.py ─────────────────────────────
WINDOW = 30    # frames per inference window
STRIDE = 15    # run inference every STRIDE frames

# OpenPose 18-pt to VSViG 15-pt canonical ordering
# Groups into 5 body parts (3 points each):
#   Head[0-2]:  nose, left_eye, right_eye
#   R_Arm[3-5]: right_shoulder, right_elbow, right_wrist
#   L_Arm[6-8]: left_shoulder, left_elbow, left_wrist
#   R_Leg[9-11]: right_hip, right_knee, right_ankle
#   L_Leg[12-14]: left_hip, left_knee, left_ankle
# Dropped: neck(1), right_ear(16), left_ear(17)
OPENPOSE_18_TO_VSVIG_15 = [0, 15, 14, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]

# OpenPose 18-pt skeleton edges for visualisation overlay
SKELETON_EDGES = [
    (0, 1),   # nose  → neck
    (1, 2),   # neck  → right_shoulder
    (2, 3),   # r_shoulder → r_elbow
    (3, 4),   # r_elbow    → r_wrist
    (1, 5),   # neck       → left_shoulder
    (5, 6),   # l_shoulder → l_elbow
    (6, 7),   # l_elbow    → l_wrist
    (1, 8),   # neck       → right_hip
    (8, 9),   # r_hip      → r_knee
    (9, 10),  # r_knee     → r_ankle
    (1, 11),  # neck       → left_hip
    (11, 12), # l_hip      → l_knee
    (12, 13), # l_knee     → l_ankle
    (0, 14),  # nose       → right_eye
    (0, 15),  # nose       → left_eye
    (14, 16), # r_eye      → r_ear
    (15, 17), # l_eye      → l_ear
]

# Colour palette (BGR) — green → orange → red along probability
_PALETTE_PT = np.array([(0, 220, 0), (0, 180, 80), (0, 140, 160),
                         (0, 100, 220), (0, 60, 255)], dtype=np.float32)


def _prob_color(prob: float):
    """Map [0,1] fall probability to a BGR colour (green → red)."""
    idx = min(prob * 5.0, 4.0)
    lo = int(idx); hi = min(lo + 1, 4)
    frac = idx - lo
    c = _PALETTE_PT[lo] * (1 - frac) + _PALETTE_PT[hi] * frac
    return tuple(int(v) for v in c)


def _patches_hwc_to_chw(patches_np: np.ndarray) -> torch.Tensor:
    """Convert (15, H, W, 3) uint8 HWC → float32 (15, 3, H, W) tensor."""
    t = torch.from_numpy(patches_np).permute(0, 3, 1, 2).float()
    return t


def _kpts18_to_15(kpts18_3d: np.ndarray) -> np.ndarray:
    """(18, 3) OpenPose → (15, 3) VSViG canonical ordering."""
    return kpts18_3d[OPENPOSE_18_TO_VSVIG_15]


class FallDetectionWorker(BaseWorker):
    """
    Sliding-window fall detection inference worker.

    Accumulates per-frame outputs from upstream workers into temporal
    buffers, then runs the EnhancedVSViG model every STRIDE frames
    to produce a fall probability.

    Input: {
        "frame": np.ndarray,
        "pose": pose_data_dict,
        "patches": np.ndarray (15, 32, 32, 3),
        "global_patch": np.ndarray (64, 64, 3),
        "kinematic_features": np.ndarray (25,)
    }
    Output: {
        "fall_detection": {
            "probability": float,
            "is_fall": bool,
            "label": str,
            "inference_count": int,
            "fall_detections": int,
            "frame_count": int,
            "avg_inference_time_ms": float,
            "skeleton_edges": list,
            "overlay_color": tuple
        }
    }
    """

    def __init__(self, model_path: Optional[str] = None,
                 model_type: str = 'base'):
        super().__init__(name="fall_detection", model_path=model_path)
        self._model = None
        self._model_type = model_type
        self._device = None
        self._use_global = True
        self._use_kinematic = True

        # Rolling buffers (most-recent WINDOW entries)
        self._patches_buf: deque = deque(maxlen=WINDOW)
        self._kpts18_buf: deque = deque(maxlen=WINDOW)
        self._global_patch_buf: deque = deque(maxlen=WINDOW)
        self._kinematic_buf: deque = deque(maxlen=WINDOW)

        # Inference state
        self._frame_count = 0
        self._last_prob = 0.0
        self._last_label = "Initialising…"
        self._inference_count = 0
        self._fall_detections = 0
        self._inference_times: deque = deque(maxlen=30)

        # Default thresholds
        self._threshold = 0.5
        self._alert_threshold = 0.75

    def load_model(self):
        """Load the EnhancedVSViG model from checkpoint."""
        import torch

        self._device = torch.device(
            'cuda' if torch.cuda.is_available() else 'cpu'
        )

        # Resolve model path
        if self.model_path is None:
            # Default: look relative to ml_manager directory
            base_dir = Path(__file__).resolve().parent.parent.parent
            self.model_path = str(base_dir / "models" / "VSViGFall.pth")

        model_path = Path(self.model_path)
        if not model_path.exists():
            print(f"❌ Fall detection model not found: {model_path}")
            self.is_loaded = False
            return

        print(f"🎯 Loading fall detection model from: {model_path}")
        print(f"   Device: {self._device}")
        print(f"   Threshold: {self._threshold}, Alert Threshold: {self._alert_threshold}")

        try:
            checkpoint = torch.load(
                model_path, map_location='cpu', weights_only=False
            )

            # If this is a full training checkpoint, recover config
            if isinstance(checkpoint, dict) and 'model_state_dict' in checkpoint:
                self._use_global = checkpoint.get(
                    'use_global_patches', self._use_global
                )
                self._use_kinematic = checkpoint.get(
                    'use_kinematic_features', self._use_kinematic
                )
                state_dict = checkpoint['model_state_dict']
                epoch = checkpoint.get('epoch', '?')
                best_val = checkpoint.get('best_val_loss', None)
                print(f"   Epoch {epoch}" +
                      (f", best_val_loss={best_val:.4f}" if best_val else ""))
            else:
                # Raw state_dict — try to recover config from sibling checkpoints
                state_dict = checkpoint
                ckpt_dir = model_path.parent / 'checkpoints'
                if ckpt_dir.is_dir():
                    for cf in sorted(ckpt_dir.glob('checkpoint_epoch_*.pth'),
                                     reverse=True):
                        try:
                            tmp = torch.load(cf, map_location='cpu',
                                             weights_only=False)
                            if isinstance(tmp, dict) and 'model_state_dict' in tmp:
                                cg = tmp.get('use_global_patches', None)
                                ck = tmp.get('use_kinematic_features', None)
                                if cg is not None and ck is not None:
                                    self._use_global = cg
                                    self._use_kinematic = ck
                                    print(f"   Config recovered from {cf.name}: "
                                          f"global={self._use_global}, "
                                          f"kinematic={self._use_kinematic}")
                                    break
                        except Exception:
                            pass
                else:
                    print("   ℹ️  Assuming use_global_patches=True, "
                          "use_kinematic_features=True")

            # Build model
            from steps.fall_detection.VSViG_enhanced import (
                EnhancedVSViG_base, EnhancedVSViG_light,
            )

            factory = (EnhancedVSViG_base if self._model_type == 'base'
                       else EnhancedVSViG_light)
            self._model = factory(
                use_global_patches=self._use_global,
                use_kinematic_features=self._use_kinematic,
            )
            self._model.load_state_dict(state_dict)
            self._model.to(self._device).eval()

            n_params = sum(p.numel() for p in self._model.parameters())
            print(f"✅ Fall detection model loaded")
            print(f"   Parameters: {n_params:,}")
            print(f"   Global patches: {self._use_global}")
            print(f"   Kinematic features: {self._use_kinematic}")
            print(f"   Threshold: {self._threshold}, "
                  f"Alert: {self._alert_threshold}")

            self.is_loaded = True

        except Exception as e:
            print(f"❌ Failed to load fall detection model: {e}")
            import traceback
            traceback.print_exc()
            self.is_loaded = False

    def process(self, inputs: dict[str, Any]) -> dict[str, Any]:
        """
        Buffer per-frame data and run sliding-window inference.

        Inference runs every STRIDE frames once the buffer has WINDOW frames.
        Between inferences, returns the last known probability.

        Args:
            inputs: {
                "frame": np.ndarray (H, W, 3),
                "pose": dict with keypoints_3d (18, 3),
                "patches": np.ndarray (15, 32, 32, 3),
                "global_patch": np.ndarray (64, 64, 3),
                "kinematic_features": np.ndarray (25,)
            }

        Returns:
            {"fall_detection": dict with probability, label, stats}
        """
        self._frame_count += 1

        # ── 1. Extract per-frame data from upstream workers ───────────────

        # Pose keypoints (18, 3)
        pose_data = inputs.get("pose", {})
        if isinstance(pose_data, dict) and "keypoints_3d" in pose_data:
            kpts18_3d = np.array(pose_data["keypoints_3d"], dtype=np.float32)
        else:
            kpts18_3d = np.zeros((18, 3), dtype=np.float32)
        if kpts18_3d.shape != (18, 3):
            kpts18_3d = np.zeros((18, 3), dtype=np.float32)

        # Local patches (15, 32, 32, 3)
        patches = inputs.get("patches", None)
        if patches is None:
            patches = np.zeros((15, 32, 32, 3), dtype=np.uint8)
        patches = np.array(patches, dtype=np.uint8)
        if len(patches.shape) != 4 or patches.shape[0] != 15:
            patches = np.zeros((15, 32, 32, 3), dtype=np.uint8)

        # Global patch (64, 64, 3)
        global_patch = inputs.get("global_patch", None)
        if global_patch is None:
            global_patch = np.zeros((64, 64, 3), dtype=np.uint8)
        global_patch = np.array(global_patch, dtype=np.uint8)
        if len(global_patch.shape) != 3:
            global_patch = np.zeros((64, 64, 3), dtype=np.uint8)

        # Kinematic features (25,)
        kin_features = inputs.get("kinematic_features", None)
        if kin_features is None:
            kin_features = np.zeros(25, dtype=np.float32)
        kin_features = np.array(kin_features, dtype=np.float32)
        if kin_features.shape != (25,):
            kin_features = np.zeros(25, dtype=np.float32)

        # ── 2. Buffer update ─────────────────────────────────────────────

        self._kpts18_buf.append(kpts18_3d)
        self._patches_buf.append(patches)
        self._global_patch_buf.append(global_patch)
        self._kinematic_buf.append(kin_features)

        # ── 3. Run inference when buffer is full and stride condition met ─

        if (len(self._kpts18_buf) == WINDOW and
                self._frame_count % STRIDE == 0):
            self._run_inference()

        # ── 4. Build result ──────────────────────────────────────────────

        is_fall = self._last_prob >= self._threshold
        avg_inf = (sum(self._inference_times) / len(self._inference_times)
                   if self._inference_times else 0.0)

        return {
            "fall_detection": {
                "probability": round(self._last_prob, 4),
                "is_fall": is_fall,
                "label": self._last_label,
                "inference_count": self._inference_count,
                "fall_detections": self._fall_detections,
                "frame_count": self._frame_count,
                "avg_inference_time_ms": round(avg_inf * 1000, 1),
                "threshold": self._threshold,
                "alert_threshold": self._alert_threshold,
                "skeleton_edges": SKELETON_EDGES,
                "overlay_color": _prob_color(self._last_prob),
            }
        }

    def _run_inference(self):
        """Run model inference on the current sliding window."""
        import time
        t0 = time.time()

        try:
            kpts_list = list(self._kpts18_buf)      # T=30, each (18,3)
            patches_list = list(self._patches_buf)   # T=30, each (15,32,32,3)

            # ── Local patches ────────────────────────────────────────────
            patches_tensors = []
            kpts15_all = []
            for k18, p in zip(kpts_list, patches_list):
                patches_tensors.append(_patches_hwc_to_chw(p))
                kpts15_all.append(_kpts18_to_15(k18))

            # (30, 15, 3, 32, 32)
            patches_t = torch.stack(patches_tensors)
            # (30, 15, 3)
            kpts15_t = torch.from_numpy(
                np.stack(kpts15_all, axis=0)
            ).float()

            # ── Global patches ───────────────────────────────────────────
            global_t = None
            if self._use_global:
                gp_list = list(self._global_patch_buf)
                global_t = torch.from_numpy(
                    np.stack(gp_list, axis=0)
                ).float()  # (30, 64, 64, 3)

            # ── Kinematic features ───────────────────────────────────────
            kin_t = None
            if self._use_kinematic:
                # Use the most recent kinematic feature vector
                kin_arr = list(self._kinematic_buf)[-1]
                kin_t = torch.from_numpy(kin_arr).float()  # (25,)

            # ── Model forward ────────────────────────────────────────────
            with torch.no_grad():
                lp = patches_t.unsqueeze(0).to(self._device)   # (1,30,15,3,32,32)
                kp = kpts15_t.unsqueeze(0).to(self._device)    # (1,30,15,3)
                gp = (global_t.unsqueeze(0).to(self._device)
                      if global_t is not None else None)        # (1,30,64,64,3)
                kf = (kin_t.unsqueeze(0).to(self._device)
                      if kin_t is not None else None)            # (1,25)

                out = self._model(
                    local_patches=lp,
                    keypoints=kp,
                    global_patches=gp,
                    kinematic_features=kf,
                    return_logits=True,
                )
                logits = out[0] if isinstance(out, tuple) else out
                prob = torch.sigmoid(logits).squeeze().item()

            # ── State update ─────────────────────────────────────────────
            self._last_prob = prob
            self._inference_count += 1
            elapsed = time.time() - t0
            self._inference_times.append(elapsed)

            is_fall = prob >= self._threshold
            if is_fall:
                self._fall_detections += 1
                print(f"⚠️ [FallWorker] FALL DETECTED! Prob: {prob:.4f}")
            else:
                if prob > 0.1:  # Only log significant non-fall probabilities
                    print(f"ℹ️ [FallWorker] Inference: prob={prob:.4f}")

            if prob >= self._alert_threshold:
                self._last_label = "⚠ FALL DETECTED"
            elif prob >= self._threshold:
                self._last_label = "FALL"
            elif prob >= self._threshold * 0.7:
                self._last_label = "Caution"
            else:
                self._last_label = "Normal"

        except Exception as e:
            warnings.warn(f"[FallDetection] Inference error: {e}")
            import traceback
            traceback.print_exc()

    def reset_state(self):
        """Reset all internal buffers and counters."""
        self._patches_buf.clear()
        self._kpts18_buf.clear()
        self._global_patch_buf.clear()
        self._kinematic_buf.clear()
        self._frame_count = 0
        self._last_prob = 0.0
        self._last_label = "Initialising…"
        self._inference_count = 0
        self._fall_detections = 0
        self._inference_times.clear()

    def update_config(self, config: dict[str, Any]):
        """Update fall detection configuration at runtime.

        Supported keys:
            - threshold (float): Fall detection threshold 0–1 (default: 0.5)
            - alert_threshold (float): High-confidence alert threshold (default: 0.75)
        """
        if "threshold" in config:
            self._threshold = float(config["threshold"])
        if "alert_threshold" in config:
            self._alert_threshold = float(config["alert_threshold"])
        print(f"[FallDetection] Config updated: threshold={self._threshold}, "
              f"alert_threshold={self._alert_threshold}")

    def get_config(self) -> dict[str, Any]:
        """Return current configuration."""
        return {
            "threshold": self._threshold,
            "alert_threshold": self._alert_threshold,
            "model_type": self._model_type,
            "use_global_patches": self._use_global,
            "use_kinematic_features": self._use_kinematic,
            "window_size": WINDOW,
            "stride": STRIDE,
            "device": str(self._device) if self._device else "unknown",
        }

    def unload_model(self):
        """Release model and GPU resources."""
        if self._model is not None:
            del self._model
            self._model = None
        self._device = None
        self.reset_state()
        self.is_loaded = False

        # Free GPU memory
        try:
            import torch
            if torch.cuda.is_available():
                torch.cuda.empty_cache()
        except Exception:
            pass

        print(f"🎯 Fall detection model unloaded")

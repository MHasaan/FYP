"""
Global Patch Extraction Worker — Full-body letterboxed crop extraction.

Uses the global patch extractor from the fall detection research:
  - Bounding box from valid keypoints with configurable padding
  - EMA temporal smoothing of bounding boxes across frames
  - Square letterboxed crops (preserves aspect ratio)
  - Produces (64, 64, 3) uint8 patch per frame

Depends on: pose worker output (OpenPose-18 format keypoints)
"""

import numpy as np
from typing import Any, Optional
from manager.workers.base_worker import BaseWorker


class GlobalPatchWorker(BaseWorker):
    """
    Global patch extraction worker that produces full-body crops.

    Maintains EMA bounding-box state across frames for temporal smoothing,
    matching the production inference pipeline in detect_fall_production.py.

    Input: {"frame": np.ndarray, "pose": pose_data_dict}
    Output: {"global_patch": np.ndarray (64, 64, 3),
             "global_bbox": dict}
    """

    def __init__(self, model_path: Optional[str] = None):
        super().__init__(name="global_patch", model_path=model_path)
        self._extract_fn = None
        # EMA state for temporal bounding-box smoothing
        self._prev_bbox = None
        # Default configuration
        self._target_size = (64, 64)
        self._padding_ratio = 0.2
        self._ema_alpha = 0.2  # 20% current frame, 80% previous

    def load_model(self):
        """Load the global patch extraction function (no model weights needed)."""
        print(f"🌍 Loading global patch extraction module...")
        try:
            from steps.global_patch_extraction.global_patch_extractor import (
                extract_global_patch,
            )
            self._extract_fn = extract_global_patch
            self.is_loaded = True
            print(f"✅ Global patch extraction module loaded")
            print(f"   Target size: {self._target_size}")
            print(f"   Padding ratio: {self._padding_ratio}")
            print(f"   EMA alpha: {self._ema_alpha}")
        except ImportError as e:
            print(f"❌ Failed to load global patch extraction module: {e}")
            self.is_loaded = False

    def process(self, inputs: dict[str, Any]) -> dict[str, Any]:
        """
        Extract a global body-region patch from frame + pose keypoints.

        Args:
            inputs: {
                "frame": np.ndarray (H, W, 3) — BGR frame,
                "pose": {
                    "keypoints_xy": np.ndarray (18, 2),
                    "confidences": np.ndarray (18,),
                    "keypoints_3d": np.ndarray (18, 3)
                }
            }

        Returns:
            {
                "global_patch": np.ndarray (64, 64, 3) — letterboxed crop,
                "global_bbox": dict — bounding box info with smoothing metadata
            }
        """
        frame = inputs["frame"]
        pose_data = inputs["pose"]

        # Get the (18, 3) keypoints array from pose output
        if isinstance(pose_data, dict) and "keypoints_3d" in pose_data:
            kpts_3d = pose_data["keypoints_3d"]
        elif isinstance(pose_data, dict) and "keypoints_xy" in pose_data:
            # Build (18, 3) from xy + confidences
            kpts_xy = pose_data["keypoints_xy"]
            confs = pose_data.get("confidences", np.ones(kpts_xy.shape[0]))
            kpts_3d = np.concatenate(
                [kpts_xy, confs[:, np.newaxis]], axis=1
            )
        else:
            # Fallback: zero keypoints
            kpts_3d = np.zeros((18, 3), dtype=np.float32)

        # Ensure correct shape and type
        kpts_3d = np.array(kpts_3d, dtype=np.float32)
        if kpts_3d.shape != (18, 3):
            kpts_3d = np.zeros((18, 3), dtype=np.float32)

        # Run extraction with EMA temporal smoothing
        try:
            global_patch, bbox_info = self._extract_fn(
                img=frame,
                kpts=kpts_3d,
                target_size=self._target_size,
                padding_ratio=self._padding_ratio,
                prev_bbox=self._prev_bbox,
                ema_alpha=self._ema_alpha,
            )

            # Update EMA state for next frame — use smoothed bbox if available
            smoothed = bbox_info.get('smoothed_bbox', None)
            if smoothed is not None:
                self._prev_bbox = np.array(smoothed, dtype=np.float32)
            else:
                self._prev_bbox = np.array(
                    [bbox_info['x_min'], bbox_info['y_min'],
                     bbox_info['x_max'], bbox_info['y_max']],
                    dtype=np.float32
                )

        except Exception as e:
            print(f"[GlobalPatch] Error: {e}")
            global_patch = np.zeros(
                (self._target_size[0], self._target_size[1], 3), dtype=np.uint8
            )
            bbox_info = {"error": str(e), "method": "failed"}

        return {
            "global_patch": global_patch,
            "global_bbox": bbox_info,
        }

    def reset_state(self):
        """Reset the EMA bounding-box state (e.g., on camera/source change)."""
        self._prev_bbox = None

    def update_config(self, config: dict[str, Any]):
        """Update global patch extraction configuration at runtime.

        Supported keys:
            - target_size (tuple[int,int]): Output crop size (default: (64, 64))
            - padding_ratio (float): Extra padding around body (default: 0.2)
            - ema_alpha (float): EMA smoothing coefficient (default: 0.2)
        """
        if "target_size" in config:
            ts = config["target_size"]
            if isinstance(ts, (list, tuple)) and len(ts) == 2:
                self._target_size = tuple(int(x) for x in ts)
        if "padding_ratio" in config:
            self._padding_ratio = float(config["padding_ratio"])
        if "ema_alpha" in config:
            self._ema_alpha = float(config["ema_alpha"])
        print(f"[GlobalPatch] Config updated: target_size={self._target_size}, "
              f"padding={self._padding_ratio}, ema_alpha={self._ema_alpha}")

    def get_config(self) -> dict[str, Any]:
        """Return current configuration."""
        return {
            "target_size": self._target_size,
            "padding_ratio": self._padding_ratio,
            "ema_alpha": self._ema_alpha,
        }

    def unload_model(self):
        """Release resources."""
        self._extract_fn = None
        self._prev_bbox = None
        self.is_loaded = False
        print(f"🌍 Global patch extraction module unloaded")

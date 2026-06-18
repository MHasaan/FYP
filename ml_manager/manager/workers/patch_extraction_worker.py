"""
Patch Extraction Worker — Extracts 15 local body-part patches from pose keypoints.

Uses the enhanced patch extraction pipeline from the fall detection research:
  - Gaussian-weighted crops around each keypoint
  - Confidence-aware extraction with anatomical fallback estimation
  - Produces (15, 32, 32, 3) uint8 patches per frame

Depends on: pose worker output (OpenPose-18 format keypoints)
"""

import numpy as np
from typing import Any, Optional
from manager.workers.base_worker import BaseWorker


class PatchExtractionWorker(BaseWorker):
    """
    Patch extraction worker that produces local body-part patches.

    Supports two keypoint orderings via `indices_name`:
      - "fall"    → FALL_INDICES, outputs keys: patches / valid_mask / patch_quality
      - "seizure" → SEIZURE_INDICES, outputs keys: patches_seizure / valid_mask_seizure / patch_quality_seizure

    Input: {"frame": np.ndarray, "pose": pose_data_dict}
    """

    def __init__(self, model_path: Optional[str] = None, indices_name: str = "fall"):
        super().__init__(name="patch_extraction", model_path=model_path)
        self._indices_name = indices_name
        self._output_prefix = "" if indices_name == "fall" else f"{indices_name}_"
        self._extract_fn = None
        self._indices_to_keep = None  # set in load_model
        # Default configuration
        self._kernel_size = 128
        self._kernel_sigma = 0.3
        self._scale = 1 / 4  # 128 * 0.25 = 32px output patches
        self._min_confidence = 0.1

    def load_model(self):
        """Load the patch extraction function (no model weights needed)."""
        print(f"🧩 Loading patch extraction module (indices={self._indices_name})...")
        try:
            from steps.patch_extraction.enhanced_extract_patches import (
                extract_patches_with_confidence,
                FALL_INDICES,
                SEIZURE_INDICES,
            )
            self._extract_fn = extract_patches_with_confidence
            self._indices_to_keep = (
                FALL_INDICES if self._indices_name == "fall" else SEIZURE_INDICES
            )
            self.is_loaded = True
            print(f"✅ Patch extraction module loaded ({self._indices_name} ordering)")
            print(f"   Kernel size: {self._kernel_size}")
            print(f"   Kernel sigma: {self._kernel_sigma}")
            print(f"   Output scale: {self._scale} ({int(self._kernel_size * self._scale)}px)")
            print(f"   Min confidence: {self._min_confidence}")
        except ImportError as e:
            print(f"❌ Failed to load patch extraction module: {e}")
            self.is_loaded = False

    def process(self, inputs: dict[str, Any]) -> dict[str, Any]:
        """
        Extract local body-part patches from frame + pose keypoints.

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
                "patches": np.ndarray (15, 32, 32, 3) — local patches,
                "valid_mask": np.ndarray (15,) — which patches had valid keypoints,
                "patch_quality": dict — quality metrics
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
            # Fallback: zero keypoints → all patches will be estimated/black
            kpts_3d = np.zeros((18, 3), dtype=np.float32)

        # Ensure correct shape and type
        kpts_3d = np.array(kpts_3d, dtype=np.float32)
        if kpts_3d.shape != (18, 3):
            kpts_3d = np.zeros((18, 3), dtype=np.float32)

        # Run extraction
        try:
            patches, valid_mask, debug_info = self._extract_fn(
                img=frame,
                kpts=kpts_3d,
                kernel_size=self._kernel_size,
                kernel_sigma=self._kernel_sigma,
                scale=self._scale,
                min_confidence=self._min_confidence,
                debug=False,
                indices_to_keep=self._indices_to_keep,
            )

            # Extract quality summary
            patch_quality = debug_info.get("summary", {})

        except Exception as e:
            print(f"[PatchExtraction] Error: {e}")
            output_size = int(self._kernel_size * self._scale)
            patches = np.zeros((15, output_size, output_size, 3), dtype=np.uint8)
            valid_mask = np.zeros(15, dtype=bool)
            patch_quality = {
                "total_keypoints": 15,
                "valid_keypoints": 0,
                "fallback_used_count": 0,
                "success_rate": 0.0,
                "error": str(e),
            }

        prefix = self._output_prefix
        return {
            f"{prefix}patches":       patches,
            f"{prefix}valid_mask":    valid_mask,
            f"{prefix}patch_quality": patch_quality,
        }

    def update_config(self, config: dict[str, Any]):
        """Update patch extraction configuration at runtime.

        Supported keys:
            - kernel_size (int): Gaussian kernel size (default: 128)
            - kernel_sigma (float): Gaussian sigma (default: 0.3)
            - min_confidence (float): Minimum keypoint confidence (default: 0.1)
        """
        if "kernel_size" in config:
            self._kernel_size = int(config["kernel_size"])
        if "kernel_sigma" in config:
            self._kernel_sigma = float(config["kernel_sigma"])
        if "min_confidence" in config:
            self._min_confidence = float(config["min_confidence"])
        print(f"[PatchExtraction] Config updated: kernel={self._kernel_size}, "
              f"sigma={self._kernel_sigma}, min_conf={self._min_confidence}")

    def get_config(self) -> dict[str, Any]:
        """Return current configuration."""
        return {
            "kernel_size": self._kernel_size,
            "kernel_sigma": self._kernel_sigma,
            "scale": self._scale,
            "min_confidence": self._min_confidence,
        }

    def unload_model(self):
        """Release resources."""
        self._extract_fn = None
        self.is_loaded = False
        print(f"🧩 Patch extraction module unloaded")

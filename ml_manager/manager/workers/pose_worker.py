"""
Pose Estimation Worker — RTMPose-based pose detection with intelligent tracking.

Uses the full research pipeline:
  - RTMPose (via rtmlib) for raw 17-keypoint COCO detection
  - Automatic conversion to OpenPose 18-keypoint format
  - Intelligent temporal smoothing and movement analysis
  - Conservative keypoint estimation for occluded joints
  - Detection stability tracking per keypoint

Output is OpenPose-18 format: (18, 2) xy + (18,) confidences.
"""

import numpy as np
from typing import Any, Optional
from manager.workers.base_worker import BaseWorker


class PoseWorker(BaseWorker):
    """
    Pose estimation worker using RTMPose with intelligent tracking.

    Input: {"frame": np.ndarray}
    Output: {"pose": {
        "keypoints_xy": np.ndarray (18, 2),
        "confidences": np.ndarray (18,),
        "keypoints_3d": np.ndarray (18, 3),
        "quality": dict
    }}
    """

    def __init__(self, model_path: Optional[str] = None):
        super().__init__(name="pose", model_path=model_path)
        self._detector = None
        self._tracker = None
        self._detect_fn = None
        self._quality_fn = None
        # Default configuration
        self._confidence_threshold = 0.25

    def load_model(self):
        """Load RTMPose detector and initialize tracker."""
        print(f"🦴 Loading RTMPose pose estimation model...")
        try:
            from steps.pose_detection.pose_detection import (
                RTMPoseDetector,
                IntelligentPoseTracker,
                detect_pose_with_intelligent_tracking,
                assess_pose_quality_accurate,
            )

            self._detector = RTMPoseDetector()
            self._tracker = IntelligentPoseTracker()
            self._detect_fn = detect_pose_with_intelligent_tracking
            self._quality_fn = assess_pose_quality_accurate
            self.is_loaded = True
            print(f"✅ RTMPose pose estimation model loaded")
            print(f"   Confidence threshold: {self._confidence_threshold}")

        except ImportError as e:
            print(f"❌ Failed to load pose detection module: {e}")
            print(f"   Make sure rtmlib and onnxruntime are installed")
            self.is_loaded = False

    def process(self, inputs: dict[str, Any]) -> dict[str, Any]:
        """
        Run pose estimation on a frame.

        Args:
            inputs: {"frame": np.ndarray (H, W, C)}

        Returns:
            {"pose": {
                "keypoints_xy": np.ndarray (18, 2) — x, y coordinates,
                "confidences": np.ndarray (18,) — per-keypoint confidence,
                "keypoints_3d": np.ndarray (18, 3) — [x, y, conf] combined,
                "quality": dict — pose quality assessment metrics
            }}
        """
        frame = inputs["frame"]

        try:
            # Run the full intelligent detection pipeline
            kpts_xy, confidences = self._detect_fn(
                self._detector, frame, self._tracker,
                confidence_threshold=self._confidence_threshold,
            )

            # Ensure correct dtypes
            kpts_xy = np.array(kpts_xy, dtype=np.float32)
            confidences = np.array(confidences, dtype=np.float32)

            # Build combined (18, 3) array
            kpts_3d = np.concatenate(
                [kpts_xy, confidences[:, np.newaxis]], axis=1
            )

            # Assess quality
            quality = {}
            if self._quality_fn is not None:
                try:
                    quality = self._quality_fn(kpts_xy, confidences)
                except Exception:
                    quality = {}

        except Exception as e:
            print(f"[PoseWorker] Error: {e}")
            kpts_xy = np.zeros((18, 2), dtype=np.float32)
            confidences = np.zeros(18, dtype=np.float32)
            kpts_3d = np.zeros((18, 3), dtype=np.float32)
            quality = {"error": str(e)}

        return {
            "pose": {
                "keypoints_xy": kpts_xy,
                "confidences": confidences,
                "keypoints_3d": kpts_3d,
                "quality": quality,
            }
        }

    def update_config(self, config: dict[str, Any]):
        """Update pose estimation configuration at runtime.

        Supported keys:
            - confidence_threshold (float): Minimum keypoint confidence (default: 0.25)
        """
        if "confidence_threshold" in config:
            self._confidence_threshold = float(config["confidence_threshold"])
            print(f"[PoseWorker] Confidence threshold updated to {self._confidence_threshold}")

    def get_config(self) -> dict[str, Any]:
        """Return current configuration."""
        return {
            "confidence_threshold": self._confidence_threshold,
        }

    def unload_model(self):
        """Release pose model resources."""
        self._detector = None
        self._tracker = None
        self._detect_fn = None
        self._quality_fn = None
        self.model = None
        self.is_loaded = False
        print(f"🦴 Pose estimation model unloaded")

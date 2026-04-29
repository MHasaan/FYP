"""
Kinematics Worker — Fall-relevant kinematic feature extraction.

Extracts a 25-dimensional feature vector from accumulated pose keypoints:
  - Center-of-mass dynamics (trajectory, velocity, acceleration)
  - Body orientation (shoulder/hip/spine angles, compactness, extents)
  - Joint velocities per body part
  - Fall-specific indicators (downward motion, balance loss, asymmetry)

The worker internally buffers keypoints across frames because the
KinematicFeatureExtractor needs a temporal window of keypoints (default 30)
to compute meaningful velocity/acceleration features. It produces a feature
vector only when the buffer has enough frames.

Depends on: pose worker output (OpenPose-18 format keypoints)
"""

import numpy as np
from collections import deque
from typing import Any, Optional
from manager.workers.base_worker import BaseWorker


class KinematicsWorker(BaseWorker):
    """
    Kinematic feature extraction worker.

    Accumulates keypoints across frames and produces a 25-dim feature vector
    matching the KinematicFeatureExtractor.create_feature_vector() output.

    Input: {"pose": pose_data_dict}
    Output: {"kinematic_features": np.ndarray (25,),
             "kinematic_ready": bool}
    """

    # Match the sliding window used by detect_fall_production.py
    WINDOW_SIZE = 30

    def __init__(self, model_path: Optional[str] = None):
        super().__init__(name="kinematics", model_path=model_path)
        self._extractor = None
        # Internal keypoint buffer — matches the WINDOW used in fall detection
        self._kpts_buffer: deque = deque(maxlen=self.WINDOW_SIZE)
        # Cache the last valid feature vector so we return it between updates
        self._last_features: Optional[np.ndarray] = None
        # Default configuration
        self._confidence_threshold = 0.1

    def load_model(self):
        """Load the kinematic feature extractor (no model weights needed)."""
        print(f"🧮 Loading kinematic feature extraction module...")
        try:
            from steps.kinematics.kinematic_features import (
                KinematicFeatureExtractor,
            )
            self._extractor = KinematicFeatureExtractor()
            self.is_loaded = True
            print(f"✅ Kinematic feature extraction module loaded")
            print(f"   Window size: {self.WINDOW_SIZE}")
            print(f"   Feature dimensions: 25 (12 critical + 8 supporting + 5 derived)")
            print(f"   Confidence threshold: {self._confidence_threshold}")
        except ImportError as e:
            print(f"❌ Failed to load kinematic features module: {e}")
            self.is_loaded = False

    def process(self, inputs: dict[str, Any]) -> dict[str, Any]:
        """
        Buffer a frame's pose keypoints and extract kinematic features
        when the buffer is full.

        Args:
            inputs: {
                "pose": {
                    "keypoints_3d": np.ndarray (18, 3) — [x, y, conf]
                }
            }

        Returns:
            {
                "kinematic_features": np.ndarray (25,) — feature vector
                    (zeros if buffer not yet full),
                "kinematic_ready": bool — whether the feature vector is valid
            }
        """
        pose_data = inputs.get("pose", {})

        # Extract (18, 3) keypoints
        if isinstance(pose_data, dict) and "keypoints_3d" in pose_data:
            kpts_3d = np.array(pose_data["keypoints_3d"], dtype=np.float32)
        elif isinstance(pose_data, dict) and "keypoints_xy" in pose_data:
            kpts_xy = np.array(pose_data["keypoints_xy"], dtype=np.float32)
            confs = np.array(
                pose_data.get("confidences", np.ones(kpts_xy.shape[0])),
                dtype=np.float32
            )
            kpts_3d = np.concatenate(
                [kpts_xy, confs[:, np.newaxis]], axis=1
            )
        else:
            kpts_3d = np.zeros((18, 3), dtype=np.float32)

        # Ensure correct shape
        if kpts_3d.shape != (18, 3):
            kpts_3d = np.zeros((18, 3), dtype=np.float32)

        # Add to buffer
        self._kpts_buffer.append(kpts_3d)

        # Extract features when buffer is full
        if len(self._kpts_buffer) >= self.WINDOW_SIZE:
            try:
                # Stack buffered keypoints into (T, 18, 3)
                kpts_sequence = np.stack(list(self._kpts_buffer), axis=0)

                # Extract all features and create the 25-dim vector
                features_dict = self._extractor.extract_all_features(
                    kpts_sequence,
                    confidence_threshold=self._confidence_threshold,
                )
                feature_vector = self._extractor.create_feature_vector(features_dict)

                # Handle NaN/Inf values — replace with 0 for model safety
                feature_vector = np.nan_to_num(
                    feature_vector, nan=0.0, posinf=0.0, neginf=0.0
                )

                self._last_features = feature_vector

                return {
                    "kinematic_features": feature_vector,
                    "kinematic_ready": True,
                }

            except Exception as e:
                print(f"[Kinematics] Feature extraction error: {e}")
                # Fall through to return last known or zeros

        # Buffer not full or extraction failed — return last known or zeros
        if self._last_features is not None:
            return {
                "kinematic_features": self._last_features,
                "kinematic_ready": True,
            }

        return {
            "kinematic_features": np.zeros(25, dtype=np.float32),
            "kinematic_ready": False,
        }

    def reset_state(self):
        """Reset internal buffers (e.g., on camera/source change)."""
        self._kpts_buffer.clear()
        self._last_features = None

    def update_config(self, config: dict[str, Any]):
        """Update kinematic extraction configuration at runtime.

        Supported keys:
            - confidence_threshold (float): Min keypoint confidence (default: 0.1)
            - window_size (int): Temporal window size (default: 30)
        """
        if "confidence_threshold" in config:
            self._confidence_threshold = float(config["confidence_threshold"])
        if "window_size" in config:
            new_size = int(config["window_size"])
            if new_size != self.WINDOW_SIZE:
                self.WINDOW_SIZE = new_size
                # Recreate buffer with new maxlen
                old_data = list(self._kpts_buffer)
                self._kpts_buffer = deque(old_data, maxlen=self.WINDOW_SIZE)
        print(f"[Kinematics] Config updated: confidence_threshold="
              f"{self._confidence_threshold}, window_size={self.WINDOW_SIZE}")

    def get_config(self) -> dict[str, Any]:
        """Return current configuration."""
        return {
            "confidence_threshold": self._confidence_threshold,
            "window_size": self.WINDOW_SIZE,
            "buffer_fill": len(self._kpts_buffer),
        }

    def unload_model(self):
        """Release resources."""
        self._extractor = None
        self._kpts_buffer.clear()
        self._last_features = None
        self.is_loaded = False
        print(f"🧮 Kinematic feature extraction module unloaded")

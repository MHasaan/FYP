"""Kinematics step — fall-relevant kinematic feature extraction.

Extracts a 25-dimensional feature vector capturing center-of-mass dynamics,
body orientation, joint velocities, and fall-specific indicators from
temporal keypoint sequences.
"""

from steps.kinematics.kinematic_features import (
    KinematicFeatureExtractor,
    save_kinematic_features,
)

"""
keypoint_utils.py - Canonical keypoint mapping utilities for the fall detection pipeline.

Provides a single, consistent implementation of 15↔18 keypoint conversion used
across training, evaluation, batch preprocessing, and real-time detection.

OpenPose 18-keypoint layout:
  0: nose         1: neck           2: right_shoulder  3: right_elbow
  4: right_wrist  5: left_shoulder  6: left_elbow      7: left_wrist
  8: right_hip    9: right_knee    10: right_ankle    11: left_hip
 12: left_knee   13: left_ankle    14: right_eye      15: left_eye
 16: right_ear   17: left_ear

After reordering (per original train.py) and taking the first 15, the canonical
VSViG 15-point layout groups into 5 body parts (3 points each):
  Part 0 (HEAD):   0: nose         1: left_eye       2: right_eye
  Part 1 (R_ARM):  3: r_shoulder   4: r_elbow        5: r_wrist
  Part 2 (L_ARM):  6: l_shoulder   7: l_elbow        8: l_wrist
  Part 3 (R_LEG):  9: r_hip       10: r_knee        11: r_ankle
  Part 4 (L_LEG): 12: l_hip       13: l_knee        14: l_ankle
Dropped: neck (1), right_ear (16), left_ear (17)
"""

import torch
import numpy as np

# ─── Canonical mapping tables ───────────────────────────────────────────────

# Maps each of the 15 VSViG keypoints to its OpenPose-18 index.
# Derived from original train.py: new_order = [0,-3,-4] + list(np.arange(12)+2) + [1,-1,-2]
# then kpts[:,raw_order,:] = kpts[:,new_order,:]; kpts = kpts[:,:15,:]
MAPPING_15_TO_18 = [
    0,   # 15pt[0]  → 18pt[0]   nose            (HEAD)
    15,  # 15pt[1]  → 18pt[15]  left_eye        (HEAD)
    14,  # 15pt[2]  → 18pt[14]  right_eye       (HEAD)
    2,   # 15pt[3]  → 18pt[2]   right_shoulder  (R_ARM)
    3,   # 15pt[4]  → 18pt[3]   right_elbow     (R_ARM)
    4,   # 15pt[5]  → 18pt[4]   right_wrist     (R_ARM)
    5,   # 15pt[6]  → 18pt[5]   left_shoulder   (L_ARM)
    6,   # 15pt[7]  → 18pt[6]   left_elbow      (L_ARM)
    7,   # 15pt[8]  → 18pt[7]   left_wrist      (L_ARM)
    8,   # 15pt[9]  → 18pt[8]   right_hip       (R_LEG)
    9,   # 15pt[10] → 18pt[9]   right_knee      (R_LEG)
    10,  # 15pt[11] → 18pt[10]  right_ankle     (R_LEG)
    11,  # 15pt[12] → 18pt[11]  left_hip        (L_LEG)
    12,  # 15pt[13] → 18pt[12]  left_knee       (L_LEG)
    13,  # 15pt[14] → 18pt[13]  left_ankle      (L_LEG)
]


def convert_15_to_18_keypoints(keypoints_15: torch.Tensor) -> torch.Tensor:
    """Convert 15-point VSViG keypoints to 18-point OpenPose format.

    The 3 missing points (neck, right_ear, left_ear) are estimated using
    body-scale-relative symmetry rather than hardcoded pixel offsets.

    Args:
        keypoints_15: Tensor of shape ``(T, 15, 3)`` where the last dim
            is ``(x, y, confidence)``.  Also accepts ``(T, 15, 2)``
            (no confidence channel).

    Returns:
        Tensor of shape ``(T, 18, D)`` with the same dtype and device as
        the input, where *D* matches the input's last dimension.
    """
    if keypoints_15.dim() == 2:
        # Single frame: (15, D) → treat as (1, 15, D)
        return convert_15_to_18_keypoints(keypoints_15.unsqueeze(0)).squeeze(0)

    T, P, D = keypoints_15.shape
    assert P == 15, f"Expected 15 keypoints, got {P}"

    keypoints_18 = torch.zeros(T, 18, D, dtype=keypoints_15.dtype,
                               device=keypoints_15.device)

    # 1) Place the 15 known keypoints into the 18-point skeleton
    for idx_15, idx_18 in enumerate(MAPPING_15_TO_18):
        keypoints_18[:, idx_18, :] = keypoints_15[:, idx_15, :]

    has_conf = D >= 3  # whether a confidence channel is present
    min_conf = 0.1

    # Helper: per-frame validity mask (T,) based on confidence channel
    def _valid(idx_18):
        if has_conf:
            return keypoints_18[:, idx_18, 2] > min_conf
        return (keypoints_18[:, idx_18, :2].abs().sum(dim=-1)) > 0

    # 2) Estimate neck (index 1) — midpoint of shoulders
    r_shoulder_valid = _valid(2)   # right shoulder
    l_shoulder_valid = _valid(5)   # left shoulder
    both_shoulders = r_shoulder_valid & l_shoulder_valid

    if both_shoulders.any():
        keypoints_18[both_shoulders, 1, :2] = (
            keypoints_18[both_shoulders, 2, :2] +
            keypoints_18[both_shoulders, 5, :2]
        ) / 2.0
        if has_conf:
            keypoints_18[both_shoulders, 1, 2] = (
                keypoints_18[both_shoulders, 2, 2] +
                keypoints_18[both_shoulders, 5, 2]
            ) / 2.0

    # Fallback: only one shoulder visible → use that shoulder shifted towards center
    only_r = r_shoulder_valid & ~l_shoulder_valid
    if only_r.any():
        keypoints_18[only_r, 1, :2] = keypoints_18[only_r, 2, :2]
        if has_conf:
            keypoints_18[only_r, 1, 2] = keypoints_18[only_r, 2, 2] * 0.5

    only_l = l_shoulder_valid & ~r_shoulder_valid
    if only_l.any():
        keypoints_18[only_l, 1, :2] = keypoints_18[only_l, 5, :2]
        if has_conf:
            keypoints_18[only_l, 1, 2] = keypoints_18[only_l, 5, 2] * 0.5

    # 3) Estimate right_ear (index 16) — offset from right_eye away from nose
    nose_valid = _valid(0)
    r_eye_valid = _valid(14)
    l_eye_valid = _valid(15)

    has_nose_reye = nose_valid & r_eye_valid
    if has_nose_reye.any():
        # right_ear is further from nose than right_eye, along the same direction
        offset = (keypoints_18[has_nose_reye, 14, :2]
                  - keypoints_18[has_nose_reye, 0, :2])
        keypoints_18[has_nose_reye, 16, :2] = (
            keypoints_18[has_nose_reye, 14, :2] + offset * 0.5
        )
        if has_conf:
            keypoints_18[has_nose_reye, 16, 2] = (
                keypoints_18[has_nose_reye, 14, 2] * 0.6
            )

    # Fallback: only right_eye visible (no nose) — place ear at eye position
    only_reye = r_eye_valid & ~nose_valid
    if only_reye.any():
        keypoints_18[only_reye, 16, :2] = keypoints_18[only_reye, 14, :2]
        if has_conf:
            keypoints_18[only_reye, 16, 2] = keypoints_18[only_reye, 14, 2] * 0.4

    # 4) Estimate left_ear (index 17) — offset from left_eye away from nose
    has_nose_leye = nose_valid & l_eye_valid
    if has_nose_leye.any():
        offset = (keypoints_18[has_nose_leye, 15, :2]
                  - keypoints_18[has_nose_leye, 0, :2])
        keypoints_18[has_nose_leye, 17, :2] = (
            keypoints_18[has_nose_leye, 15, :2] + offset * 0.5
        )
        if has_conf:
            keypoints_18[has_nose_leye, 17, 2] = (
                keypoints_18[has_nose_leye, 15, 2] * 0.6
            )

    # Fallback: only left_eye visible (no nose) — place ear at eye position
    only_leye = l_eye_valid & ~nose_valid
    if only_leye.any():
        keypoints_18[only_leye, 17, :2] = keypoints_18[only_leye, 15, :2]
        if has_conf:
            keypoints_18[only_leye, 17, 2] = keypoints_18[only_leye, 15, 2] * 0.4

    # Cross-mirror fallback: if one ear estimated but not the other
    r_ear_valid_now = _valid(16)
    l_ear_valid_now = _valid(17)

    can_mirror_l = nose_valid & r_ear_valid_now & ~l_ear_valid_now
    if can_mirror_l.any():
        keypoints_18[can_mirror_l, 17, :2] = (
            2.0 * keypoints_18[can_mirror_l, 0, :2]
            - keypoints_18[can_mirror_l, 16, :2]
        )
        if has_conf:
            keypoints_18[can_mirror_l, 17, 2] = (
                keypoints_18[can_mirror_l, 16, 2] * 0.5
            )

    can_mirror_r = nose_valid & l_ear_valid_now & ~r_ear_valid_now
    if can_mirror_r.any():
        keypoints_18[can_mirror_r, 16, :2] = (
            2.0 * keypoints_18[can_mirror_r, 0, :2]
            - keypoints_18[can_mirror_r, 17, :2]
        )
        if has_conf:
            keypoints_18[can_mirror_r, 16, 2] = (
                keypoints_18[can_mirror_r, 17, 2] * 0.5
            )

    return keypoints_18


def convert_15_to_18_keypoints_numpy(keypoints_15: np.ndarray) -> np.ndarray:
    """Numpy wrapper around :func:`convert_15_to_18_keypoints`.

    Args:
        keypoints_15: Array of shape ``(T, 15, D)`` with D in {2, 3}.

    Returns:
        Array of shape ``(T, 18, D)``.
    """
    tensor = torch.from_numpy(keypoints_15.astype(np.float32))
    result = convert_15_to_18_keypoints(tensor)
    return result.numpy()


# ─── Body-scale utilities ───────────────────────────────────────────────────

def compute_body_scale(keypoints_18: torch.Tensor, min_scale: float = 50.0) -> torch.Tensor:
    """Estimate body scale per frame from shoulder or hip width.

    Args:
        keypoints_18: ``(T, 18, D)`` tensor with D >= 2.
        min_scale: Minimum return value (pixels) to avoid division by zero.

    Returns:
        ``(T,)`` tensor with estimated body scale per frame.
    """
    T = keypoints_18.shape[0]
    scales = torch.full((T,), min_scale, dtype=keypoints_18.dtype,
                        device=keypoints_18.device)

    # Try shoulder width first
    shoulder_dist = (keypoints_18[:, 2, :2] - keypoints_18[:, 5, :2]).norm(dim=-1)
    valid_shoulder = shoulder_dist > min_scale
    scales[valid_shoulder] = shoulder_dist[valid_shoulder]

    # Fall back to hip width for frames where shoulders aren't usable
    hip_dist = (keypoints_18[:, 8, :2] - keypoints_18[:, 11, :2]).norm(dim=-1)
    need_fallback = ~valid_shoulder & (hip_dist > min_scale)
    scales[need_fallback] = hip_dist[need_fallback]

    return scales

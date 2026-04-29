"""Global patch extraction step — full-body letterboxed crop extraction.

Extracts a temporally-smoothed, aspect-ratio-preserving global body patch
from each video frame using pose keypoints to determine the bounding region.
"""

from steps.global_patch_extraction.global_patch_extractor import (
    extract_global_patch,
    extract_global_patches_batch,
    save_global_patches,
)

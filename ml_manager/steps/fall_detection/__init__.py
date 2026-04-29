"""Fall detection step — EnhancedVSViG model definition and loading.

Contains the full EnhancedVSViG architecture (base and light variants) with
restored core graph reasoning (InterPartMR, IntraPartMR, Grapher, Part_3DCNN)
plus multi-modal enhancements (global patches, kinematic features, attention fusion).
"""

from steps.fall_detection.VSViG_enhanced import (
    EnhancedVSViG_base,
    EnhancedVSViG_light,
    EnhancedSTViG,
)

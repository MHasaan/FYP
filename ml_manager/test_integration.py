"""Smoke test: verify all new workers, step __init__.py, and DAG logic."""
import sys
sys.path.insert(0, '.')

print("=" * 60)
print("PHASE 1: Step Module Imports")
print("=" * 60)

from steps.global_patch_extraction import extract_global_patch, extract_global_patches_batch, save_global_patches
print("  [OK] global_patch_extraction __init__")

from steps.kinematics import KinematicFeatureExtractor, save_kinematic_features
print("  [OK] kinematics __init__")

from steps.fall_detection import EnhancedVSViG_base, EnhancedVSViG_light, EnhancedSTViG
print("  [OK] fall_detection __init__")

from steps.pose_detection import RTMPoseDetector, IntelligentPoseTracker, detect_pose_with_intelligent_tracking
print("  [OK] pose_detection __init__")

from steps.patch_extraction import extract_patches_with_confidence
print("  [OK] patch_extraction __init__")

from steps.common import MAPPING_15_TO_18, convert_15_to_18_keypoints
print("  [OK] common __init__")


print()
print("=" * 60)
print("PHASE 2: Worker Imports + Instantiation")
print("=" * 60)

from manager.workers.global_patch_worker import GlobalPatchWorker
from manager.workers.kinematics_worker import KinematicsWorker
from manager.workers.fall_detection_worker import FallDetectionWorker

w1 = GlobalPatchWorker()
w2 = KinematicsWorker()
w3 = FallDetectionWorker()
print(f"  [OK] {w1}")
print(f"  [OK] {w2}")
print(f"  [OK] {w3}")


print()
print("=" * 60)
print("PHASE 3: Worker load_model() Tests")
print("=" * 60)

# Test GlobalPatchWorker loading
w1.load_model()
print(f"  GlobalPatchWorker loaded: {w1.is_loaded}")
assert w1.is_loaded, "GlobalPatchWorker failed to load"

# Test KinematicsWorker loading
w2.load_model()
print(f"  KinematicsWorker loaded: {w2.is_loaded}")
assert w2.is_loaded, "KinematicsWorker failed to load"

# FallDetectionWorker requires model weights - just verify it doesn't crash
# (model file may not exist locally)
print("  FallDetectionWorker: skipping load_model (requires model weights)")


print()
print("=" * 60)
print("PHASE 4: Functional Tests with Dummy Data")
print("=" * 60)

import numpy as np

# Test GlobalPatchWorker with a dummy frame + pose
dummy_frame = np.random.randint(0, 255, (480, 640, 3), dtype=np.uint8)
dummy_pose = {
    "keypoints_xy": np.random.rand(18, 2).astype(np.float32) * [640, 480],
    "confidences": np.random.rand(18).astype(np.float32),
    "keypoints_3d": np.zeros((18, 3), dtype=np.float32),
}
dummy_pose["keypoints_3d"][:, :2] = dummy_pose["keypoints_xy"]
dummy_pose["keypoints_3d"][:, 2] = dummy_pose["confidences"]

result1 = w1.process({"frame": dummy_frame, "pose": dummy_pose})
assert "global_patch" in result1, "Missing global_patch in output"
assert "global_bbox" in result1, "Missing global_bbox in output"
assert result1["global_patch"].shape == (64, 64, 3), f"Wrong shape: {result1['global_patch'].shape}"
print(f"  [OK] GlobalPatchWorker.process(): patch shape={result1['global_patch'].shape}, "
      f"method={result1['global_bbox'].get('method', 'unknown')}")

# Test KinematicsWorker - process multiple frames to fill buffer
for i in range(30):
    result2 = w2.process({"pose": dummy_pose})

assert "kinematic_features" in result2, "Missing kinematic_features in output"
assert "kinematic_ready" in result2, "Missing kinematic_ready in output"
assert result2["kinematic_features"].shape == (25,), f"Wrong shape: {result2['kinematic_features'].shape}"
assert result2["kinematic_ready"] == True, "Should be ready after 30 frames"
print(f"  [OK] KinematicsWorker.process(): features shape={result2['kinematic_features'].shape}, "
      f"ready={result2['kinematic_ready']}")


print()
print("=" * 60)
print("PHASE 5: DAG Topology Test")
print("=" * 60)

from manager.pipeline import Pipeline
from manager.workers.base_worker import BaseWorker

class DummyWorker(BaseWorker):
    def __init__(self):
        super().__init__(name="dummy")
        self.is_loaded = True
    def load_model(self): pass
    def process(self, inputs): return {}
    def unload_model(self): pass

# Build the fall detection pipeline DAG
DEPENDENCIES = {
    "pose": [],
    "patch_extraction": ["pose"],
    "global_patch": ["pose"],
    "kinematics": ["pose"],
    "fall_detection": ["pose", "patch_extraction", "global_patch", "kinematics"],
}

INPUT_KEYS = {
    "pose": ["frame"],
    "patch_extraction": ["frame", "pose"],
    "global_patch": ["frame", "pose"],
    "kinematics": ["pose"],
    "fall_detection": ["frame", "pose", "patches", "global_patch", "kinematic_features"],
}

pipeline = Pipeline()
test_models = ["pose", "patch_extraction", "global_patch", "kinematics", "fall_detection"]
for model_name in test_models:
    deps = [d for d in DEPENDENCIES.get(model_name, []) if d in test_models]
    input_keys = INPUT_KEYS.get(model_name, [])
    pipeline.add_step(
        name=model_name,
        worker=DummyWorker(),
        depends_on=deps,
        input_keys=input_keys,
    )

plan = pipeline.get_execution_plan()
print(f"  Execution plan ({len(plan)} levels):")
for i, level in enumerate(plan):
    print(f"    Level {i}: [{', '.join(level)}]")

# Verify topology:
# Level 0: pose (no dependencies)
# Level 1: patch_extraction, global_patch, kinematics (all depend on pose only, run in parallel)
# Level 2: fall_detection (depends on all Level 1 outputs)
assert len(plan) == 3, f"Expected 3 levels, got {len(plan)}"
assert plan[0] == ["pose"], f"Level 0 should be ['pose'], got {plan[0]}"
assert set(plan[1]) == {"patch_extraction", "global_patch", "kinematics"}, f"Level 1 wrong: {plan[1]}"
assert plan[2] == ["fall_detection"], f"Level 2 should be ['fall_detection'], got {plan[2]}"
print("  [OK] DAG topology verified: 3 levels, correct parallel grouping")

pipeline.shutdown()

print()
print("=" * 60)
print("ALL TESTS PASSED")
print("=" * 60)

"""
test_pose_detection.py — Standalone pose-detection test on a video file.

Reproduces the exact same pose-detection flow as detect_fall_production.py:
  1. RTMPoseDetector() → raw 17-keypoint COCO detection
  2. IntelligentPoseTracker() + detect_pose_with_intelligent_tracking()
     → temporal smoothing, movement analysis, conservative estimation
  3. Outputs OpenPose-18 format: (18, 2) xy + (18,) confidences

Usage (inside Docker container):
  python test_pose_detection.py --source /videos/recordings/sample.mp4

Usage (from host):
  docker compose exec ml_manager python test_pose_detection.py \
      --source /videos/recordings/sample.mp4
"""

import argparse
import sys
import time
import json
import numpy as np

# ─── Import exactly the same modules as detect_fall_production.py ─────────────
from steps.pose_detection.pose_detection import (
    RTMPoseDetector,
    IntelligentPoseTracker,
    detect_pose_with_intelligent_tracking,
    assess_pose_quality_accurate,
)

# ─── Also test that patch extraction works with the pose output ───────────────
from steps.patch_extraction.enhanced_extract_patches import (
    extract_patches_with_confidence,
)


def main():
    parser = argparse.ArgumentParser(description="Test pose detection on video")
    parser.add_argument("--source", required=True, help="Path to video file")
    parser.add_argument("--max_frames", type=int, default=60,
                        help="Max frames to process (default: 60)")
    parser.add_argument("--skip_patch", action="store_true",
                        help="Skip patch extraction test")
    args = parser.parse_args()

    # OpenCV — imported here because it's heavy
    import cv2

    # ── 1. Open video ─────────────────────────────────────────────────────────
    cap = cv2.VideoCapture(args.source)
    if not cap.isOpened():
        print(f"❌ Cannot open video: {args.source}")
        sys.exit(1)

    fps = cap.get(cv2.CAP_PROP_FPS)
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))

    print(f"📹 Video: {args.source}")
    print(f"   Resolution: {width}×{height} @ {fps:.1f} fps")
    print(f"   Total frames: {total_frames}")
    print(f"   Processing: up to {args.max_frames} frames")
    print()

    # ── 2. Initialise detector + tracker (same as FallDetector.__init__) ───────
    print("🦴 Initialising RTMPose detector…")
    rtm_detector = RTMPoseDetector()
    tracker = IntelligentPoseTracker()
    print("✅ Pose detector ready")
    print()

    # ── 3. Process frames (same logic as FallDetector.process_frame) ──────────
    frame_results = []
    pose_times = []
    patch_times = []
    frame_idx = 0

    print("Processing frames…")
    print("-" * 70)

    while frame_idx < args.max_frames:
        ret, frame = cap.read()
        if not ret:
            break

        # — Pose detection (exact same call as detect_fall_production.py L236-238)
        t0 = time.perf_counter()
        kpts18_xy, conf18 = detect_pose_with_intelligent_tracking(
            rtm_detector, frame, tracker
        )
        pose_ms = (time.perf_counter() - t0) * 1000
        pose_times.append(pose_ms)

        # — Build (18, 3) array (same as detect_fall_production.py L239-240)
        kpts18_3d = np.concatenate(
            [kpts18_xy, conf18[:, np.newaxis]], axis=1
        )  # (18, 3)

        # — Quality assessment
        quality = assess_pose_quality_accurate(kpts18_xy, conf18)

        # — Patch extraction test (same call as detect_fall_production.py L269)
        patch_result = None
        if not args.skip_patch:
            t1 = time.perf_counter()
            patches, valid_mask, debug_info = extract_patches_with_confidence(
                img=frame,
                kpts=kpts18_3d,
                kernel_size=128,
                kernel_sigma=0.3,
                scale=1/4,
                min_confidence=0.1,
            )
            patch_ms = (time.perf_counter() - t1) * 1000
            patch_times.append(patch_ms)
            patch_result = {
                "shape": list(patches.shape),
                "valid_count": int(np.sum(valid_mask)),
                "time_ms": round(patch_ms, 1),
            }

        # — Count high-confidence keypoints
        high_conf = int(np.sum(conf18 > 0.5))
        med_conf = int(np.sum((conf18 > 0.25) & (conf18 <= 0.5)))

        result = {
            "frame": frame_idx,
            "keypoints_shape": list(kpts18_xy.shape),
            "confidences_shape": list(conf18.shape),
            "kpts18_3d_shape": list(kpts18_3d.shape),
            "high_conf_keypoints": high_conf,
            "med_conf_keypoints": med_conf,
            "avg_confidence": round(float(np.mean(conf18)), 3),
            "quality_grade": quality.get("detection_quality", "unknown"),
            "pose_time_ms": round(pose_ms, 1),
        }
        if patch_result:
            result["patch_extraction"] = patch_result

        frame_results.append(result)

        # Print every 10th frame
        if frame_idx % 10 == 0 or frame_idx < 5:
            patch_info = ""
            if patch_result:
                patch_info = f" | patches: {patch_result['valid_count']}/15 valid ({patch_result['time_ms']:.0f}ms)"
            print(f"  Frame {frame_idx:3d}: "
                  f"{high_conf:2d} high-conf / {med_conf} mid-conf kpts, "
                  f"avg_conf={result['avg_confidence']:.3f}, "
                  f"quality={result['quality_grade']}, "
                  f"pose={pose_ms:.0f}ms"
                  f"{patch_info}")

        frame_idx += 1

    cap.release()

    # ── 4. Summary ────────────────────────────────────────────────────────────
    print("-" * 70)
    print()
    print("=" * 70)
    print("POSE DETECTION TEST RESULTS")
    print("=" * 70)
    print(f"  Frames processed:    {len(frame_results)}")
    print(f"  Output format:       (18, 2) keypoints + (18,) confidences")
    print(f"  Combined format:     (18, 3) [x, y, conf] — same as production")
    print()

    if pose_times:
        print(f"  Pose detection timing:")
        print(f"    Mean:   {np.mean(pose_times):.1f} ms/frame")
        print(f"    Median: {np.median(pose_times):.1f} ms/frame")
        print(f"    Min:    {np.min(pose_times):.1f} ms")
        print(f"    Max:    {np.max(pose_times):.1f} ms")
        print()

    if patch_times:
        print(f"  Patch extraction timing:")
        print(f"    Mean:   {np.mean(patch_times):.1f} ms/frame")
        print(f"    Median: {np.median(patch_times):.1f} ms/frame")
        print(f"    Output: (15, 32, 32, 3) uint8 patches")
        print()

    # Quality stats
    avg_confs = [r["avg_confidence"] for r in frame_results]
    high_confs = [r["high_conf_keypoints"] for r in frame_results]
    grades = [r["quality_grade"] for r in frame_results]

    print(f"  Detection quality:")
    print(f"    Avg confidence:     {np.mean(avg_confs):.3f}")
    print(f"    Avg high-conf kpts: {np.mean(high_confs):.1f} / 18")
    print(f"    Quality grades:     "
          f"high={grades.count('high')}, "
          f"medium={grades.count('medium')}, "
          f"low={grades.count('low')}")
    print()

    # Verify output shapes match production expectations
    all_shapes_ok = all(
        r["keypoints_shape"] == [18, 2] and
        r["confidences_shape"] == [18] and
        r["kpts18_3d_shape"] == [18, 3]
        for r in frame_results
    )

    if all_shapes_ok:
        print("  ✅ All output shapes match production format:")
        print("     keypoints: (18, 2), confidences: (18,), combined: (18, 3)")
    else:
        print("  ❌ Output shape mismatch detected!")
        for r in frame_results:
            if r["keypoints_shape"] != [18, 2]:
                print(f"     Frame {r['frame']}: keypoints shape = {r['keypoints_shape']}")

    if patch_times:
        all_patches_ok = all(
            r.get("patch_extraction", {}).get("shape") == [15, 32, 32, 3]
            for r in frame_results if "patch_extraction" in r
        )
        if all_patches_ok:
            print("  ✅ All patch shapes match production format: (15, 32, 32, 3)")
        else:
            print("  ❌ Patch shape mismatch detected!")

    print()
    print("=" * 70)
    print("TEST COMPLETE")
    print("=" * 70)


if __name__ == "__main__":
    main()

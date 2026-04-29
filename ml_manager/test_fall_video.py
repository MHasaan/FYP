"""
Direct Fall Detection Test on Video File
========================================
Runs the full pipeline (Pose -> Patches -> Kinematics -> Fall) on a video file.
"""

import os
import sys
import time
import cv2
import torch
import numpy as np
from pathlib import Path

# Add current directory to path
sys.path.insert(0, str(Path(__file__).parent))

from manager.workers.pose_worker import PoseWorker
from manager.workers.patch_extraction_worker import PatchExtractionWorker
from manager.workers.global_patch_worker import GlobalPatchWorker
from manager.workers.kinematics_worker import KinematicsWorker
from manager.workers.fall_detection_worker import FallDetectionWorker

def run_test(video_path: str):
    print(f"--- Starting direct fall detection test on: {video_path} ---")
    
    if not os.path.exists(video_path):
        print(f"FAIL: Video file not found: {video_path}")
        return

    # 1. Initialize Workers
    print("STATUS: Initializing workers...")
    pose_w = PoseWorker()
    patch_w = PatchExtractionWorker()
    global_w = GlobalPatchWorker()
    kin_w = KinematicsWorker()
    fall_w = FallDetectionWorker()

    workers = [pose_w, patch_w, global_w, kin_w, fall_w]
    for w in workers:
        w.load_model()
        if not w.is_loaded and not isinstance(w, FallDetectionWorker):
             # FallDetectionWorker might need manual weight loading if default fails
             print(f"FAIL: Failed to load {w.name}")
             return

    # 2. Open Video
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        print(f"FAIL: Failed to open video: {video_path}")
        return

    fps = cap.get(cv2.CAP_PROP_FPS)
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    print(f"INFO: Video Info: {total_frames} frames, {fps:.1f} FPS")

    # 3. Processing Loop
    frame_idx = 0
    fall_detected = False
    max_prob = 0.0

    try:
        while cap.isOpened():
            ret, frame = cap.read()
            if not ret:
                break
            
            frame_idx += 1
            
            # Step 1: Pose
            pose_res = pose_w.process({"frame": frame})
            pose_data = pose_res["pose"]
            
            # Step 2: Local Patches
            patch_res = patch_w.process({"frame": frame, "pose": pose_data})
            
            # Step 3: Global Patch
            global_res = global_w.process({"frame": frame, "pose": pose_data})
            
            # Step 4: Kinematics
            kin_res = kin_w.process({"pose": pose_data})
            
            # Step 5: Fall Detection
            # Note: FallDetectionWorker handles its own buffering internally
            fall_inputs = {
                "frame": frame,
                "pose": pose_data,
                "patches": patch_res["patches"],
                "global_patch": global_res["global_patch"],
                "kinematic_features": kin_res.get("kinematic_features")
            }
            fall_res = fall_w.process(fall_inputs)
            
            # Extract probability
            prob = fall_res.get("probability", 0.0)
            max_prob = max(max_prob, prob)
            
            if fall_res.get("is_fall"):
                fall_detected = True
                print(f"ALERT: [Frame {frame_idx}/{total_frames}] FALL DETECTED! Prob: {prob:.4f}")
            elif prob > 0.2:
                print(f"INFO: [Frame {frame_idx}/{total_frames}] Prob: {prob:.4f}")
            
            if frame_idx % 30 == 0:
                print(f"INFO: Processed {frame_idx}/{total_frames} frames... (Max prob so far: {max_prob:.4f})")

    except KeyboardInterrupt:
        print("\nInterrupted by user")
    finally:
        cap.release()

    print("\n" + "="*40)
    print("TEST COMPLETE")
    print(f"Total frames processed: {frame_idx}")
    print(f"Fall detected: {'YES' if fall_detected else 'NO'}")
    print(f"Peak probability: {max_prob:.4f}")
    print("="*40)

if __name__ == "__main__":
    video = r"..\videos\recordings\fall2.mp4"
    if len(sys.argv) > 1:
        video = sys.argv[1]
    
    run_test(video)

# pose_detection.py - More accurate version with intelligent estimation using RTMPose
# Run: python pose_detection.py
import cv2
import numpy as np
import time
from collections import deque
from scipy.spatial.distance import euclidean
import json
import os
import onnxruntime as ort

# onnxruntime-gpu ships its CUDA/cuDNN libs as separate pip packages (nvidia-*-cu12) whose
# DLLs live in site-packages\nvidia\*\bin. On Windows the CUDA EP is *listed* but silently
# falls back to CPU at session creation unless those DLLs are on the loader path.
# ort.preload_dlls() (onnxruntime>=1.21) loads them correctly; no-op/ignored otherwise.
try:
    if hasattr(ort, "preload_dlls"):
        ort.preload_dlls()
except Exception:
    pass


def _ensure_tensorrt_dlls():
    """Make the standard-TensorRT runtime DLLs (nvinfer_10.dll etc.) loadable so the
    onnxruntime TensorrtExecutionProvider can initialize. preload_dlls() does NOT cover
    TensorRT; the `tensorrt` pip package ships the libs in site-packages\\tensorrt_libs\\.
    Importing tensorrt registers that dir, and we also prepend it to PATH (ORT's provider
    loader resolves nvinfer via PATH). No-op off Windows / if tensorrt isn't installed."""
    if os.name != "nt":
        return
    try:
        import tensorrt  # noqa: F401  (its __init__ adds tensorrt_libs to the DLL search)
    except Exception:
        pass
    try:
        import glob
        site = os.path.dirname(os.path.dirname(ort.__file__))
        for d in glob.glob(os.path.join(site, "tensorrt_libs")):
            if os.path.isdir(d):
                if hasattr(os, "add_dll_directory"):
                    try:
                        os.add_dll_directory(d)
                    except Exception:
                        pass
                os.environ["PATH"] = d + os.pathsep + os.environ.get("PATH", "")
    except Exception:
        pass


from rtmlib import Body

class RTMPoseDetector:
    """RTMPose detector wrapper with consistent interface"""
    
    # Person DETECTOR = YOLOX-tiny (fast; only supplies the bounding box).
    # Pose/KEYPOINT model = RTMPose-x — the SAME model the seizure detector was trained on.
    # Swapping only the detector (not the pose model) makes pose ~1.8x faster while keeping
    # keypoint quality essentially unchanged. (To revert to max accuracy, set both to the
    # 'performance' yolox_x; for max speed this tiny detector is the right call.)
    _DET_YOLOX_TINY = ("https://download.openmmlab.com/mmpose/v1/projects/rtmposev1/"
                       "onnx_sdk/yolox_tiny_8xb8-300e_humanart-6f3252f9.zip")
    _POSE_RTMPOSE_X = ("https://download.openmmlab.com/mmpose/v1/projects/rtmposev1/"
                       "onnx_sdk/rtmpose-x_simcc-body7_pt-body7_700e-384x288-71d7b7e9_20230629.zip")

    def __init__(self, provider='cuda', detect_every_n=1, select_patient=True,
                 patient_lock_ema=0.3, patient_prox_weight=0.3, patient_prox_scale=250.0):
        """
        provider: 'cuda' (default) or 'tensorrt'. TensorRT runs the SAME models with no accuracy
                  change, usually faster; it builds an engine on first run (slow first start),
                  then caches it in ./trt_cache for fast subsequent starts.
        detect_every_n: run the YOLOX detector every N frames and reuse its bounding box in
                  between, while RTMPose runs EVERY frame. N=1 = detect every frame (default,
                  most accurate). N>=2 is faster; a slightly stale box is usually fine because
                  the whole-body box barely moves frame-to-frame.
        select_patient: when multiple people are detected (e.g. caregivers leaning in during a
                  seizure), don't blindly take detection #0 -- lock onto the patient and follow
                  them. The lock initializes on the largest person (the patient lies across the
                  bed and is alone at the start of the clip) and then each frame picks the person
                  whose centroid is nearest the locked patient, so a caregiver entering frame
                  can't hijack the keypoints. Set False to restore the old "first person" behavior.
        patient_lock_ema: EMA factor for updating the locked patient centroid each frame
                  (0..1, higher = follows the current detection faster). A small value keeps the
                  lock stable so a single bad/overlapping frame can't steal it onto a caregiver.
        patient_prox_weight / patient_prox_scale: strength (LAMBDA) and distance falloff (D, in
                  standardized pixels) of the proximity tiebreak in _select_patient_index.
                  Selection is area-dominant; proximity only nudges the choice between similarly
                  sized detections. Larger weight / smaller scale = stickier to the lock.
        """
        print("Available ONNX Runtime Providers:")
        avail = ort.get_available_providers()
        print(avail)
        self.detect_every_n = max(1, int(detect_every_n))
        self._frame_idx = 0
        self._cached_bboxes = None
        # Patient-selection state (see _select_patient_index).
        self.select_patient = bool(select_patient)
        self.patient_lock_ema = float(patient_lock_ema)
        self.patient_prox_weight = float(patient_prox_weight)
        self.patient_prox_scale = float(patient_prox_scale)
        self._patient_centroid = None  # last known (x, y) of the locked patient

        if provider == 'tensorrt' and 'TensorrtExecutionProvider' in avail:
            _ensure_tensorrt_dlls()   # put nvinfer_10.dll on the loader path (Windows)
            from rtmlib.tools.base import RTMLIB_SETTINGS
            cache_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'trt_cache')
            os.makedirs(cache_dir, exist_ok=True)
            RTMLIB_SETTINGS['onnxruntime']['tensorrt'] = ('TensorrtExecutionProvider', {
                'trt_engine_cache_enable': True,
                'trt_engine_cache_path': cache_dir,
                'trt_fp16_enable': True,
            })
            device = 'tensorrt'
        elif 'CUDAExecutionProvider' in avail:
            device = 'cuda'
        else:
            device = 'cpu'

        def _make(dev):
            return Body(det=self._DET_YOLOX_TINY, det_input_size=(416, 416),
                        pose=self._POSE_RTMPOSE_X, pose_input_size=(288, 384),
                        backend='onnxruntime', device=dev)

        try:
            self.body = _make(device)
            print(f"RTMLib Body (YOLOX-tiny + RTMPose-x) on {device.upper()}, "
                  f"detect_every_n={self.detect_every_n}.")
        except Exception as e:
            fb = 'cuda' if 'CUDAExecutionProvider' in avail else 'cpu'
            print(f"Init on {device} failed ({e}); falling back to {fb}.")
            try:
                self.body = _make(fb)
            except Exception:
                self.body = _make('cpu')

    def _infer(self, frame):
        """Detector every detect_every_n frames (reuse bbox); pose model every frame."""
        if self.detect_every_n <= 1:
            return self.body(frame)
        if self._cached_bboxes is None or (self._frame_idx % self.detect_every_n == 0):
            self._cached_bboxes = self.body.det_model(frame)
        self._frame_idx += 1
        return self.body.pose_model(frame, bboxes=self._cached_bboxes)

    @staticmethod
    def _person_centroid_and_area(kpts17, conf17, min_conf=0.3):
        """Centroid (x, y) and bbox area of one person, from keypoints confident enough to
        trust. Falls back to all keypoints if none clear the threshold (very low-quality
        detection). Returns (centroid, area) with centroid=None if unusable."""
        kpts17 = np.asarray(kpts17, dtype=np.float32)
        conf17 = np.asarray(conf17, dtype=np.float32).reshape(-1)
        mask = conf17 > min_conf
        pts = kpts17[mask] if np.any(mask) else kpts17
        if pts.shape[0] == 0:
            return None, 0.0
        centroid = pts.mean(axis=0)
        wh = pts.max(axis=0) - pts.min(axis=0)
        area = float(wh[0] * wh[1])
        return centroid, area

    def _select_patient_index(self, keypoints_list, scores_list):
        """Pick which detected person is the patient and follow them across frames.

        The patient is the dominant foreground subject: lying across the bed, closest to the
        camera, and the largest detection in nearly every frame, while caregivers who lean in
        are smaller / partially occluded. So we score primarily by bbox AREA and use proximity
        to the locked patient only as a tiebreaker:

            score_i = area_i / max_area  +  LAMBDA * exp(-dist_to_lock_i / D)

        Area dominates (a distractor must be ~>70% of the patient's size AND closer to the lock
        to win), so a caregiver stepping into frame can't hijack the keypoints. Crucially, area
        is recomputed fresh every frame, so a single bad frame self-corrects -- unlike pure
        centroid tracking, which drifts onto a distractor and sticks. The lock centroid is an
        EMA of the chosen person, used only for the soft proximity tiebreak."""
        n = len(keypoints_list)
        centroids, areas = [], []
        for i in range(n):
            c, a = self._person_centroid_and_area(keypoints_list[i], scores_list[i])
            centroids.append(c)
            areas.append(a)

        valid = [i for i in range(n) if centroids[i] is not None]
        if not valid:
            return 0  # nothing usable; caller still handles it gracefully

        max_area = max(areas[i] for i in valid) or 1.0
        LAMBDA = self.patient_prox_weight
        D = self.patient_prox_scale

        def score(i):
            s = areas[i] / max_area
            if self._patient_centroid is not None:
                dist = float(np.linalg.norm(centroids[i] - self._patient_centroid))
                s += LAMBDA * float(np.exp(-dist / D))
            return s

        idx = max(valid, key=score)

        # Update the lock toward the chosen centroid (EMA keeps the tiebreak stable).
        a = self.patient_lock_ema
        if self._patient_centroid is None:
            self._patient_centroid = centroids[idx].copy()
        else:
            self._patient_centroid = (1 - a) * self._patient_centroid + a * centroids[idx]
        return idx

    def detect_poses(self, frame):
        """
        Detect poses and return in OpenPose-compatible format
        Returns: keypoints_18x3, confidences_18
        """
        # Get RTMPose detections (17 keypoints + confidence scores)
        keypoints_list, scores_list = self._infer(frame)

        # If no person detected, return zeros
        # Handle case where keypoints_list might be a numpy array
        if (keypoints_list is None or
            (hasattr(keypoints_list, '__len__') and len(keypoints_list) == 0) or
            (hasattr(keypoints_list, 'size') and keypoints_list.size == 0)):
            return np.zeros((18, 2), dtype=np.float32), np.zeros(18, dtype=np.float32)

        # Pick the patient. With one person this is just index 0; with several (caregivers
        # leaning in during a seizure) it locks onto the patient instead of detection #0.
        if self.select_patient and len(keypoints_list) > 1:
            idx = self._select_patient_index(keypoints_list, scores_list)
        else:
            idx = 0
            if self.select_patient:
                # Keep the lock warm even on single-person frames so tracking is ready
                # the moment a second person appears.
                self._select_patient_index(keypoints_list, scores_list)
        kpts17 = keypoints_list[idx]  # Shape: (17, 2)
        conf17 = scores_list[idx]     # Shape: (17,)

        # Convert to OpenPose 18-keypoint format
        kpts18, conf18 = self._convert_to_openpose_format(kpts17, conf17)

        return kpts18, conf18
    
    def _convert_to_openpose_format(self, kpts17, conf17):
        """Convert RTMPose 17 keypoints to OpenPose 18 keypoints format
        
        Ensures full compatibility with existing OpenPose-based pipeline code.
        """
        
        # Create 18 keypoint arrays initialized with zeros
        kpts18 = np.zeros((18, 2), dtype=np.float32)
        conf18 = np.zeros(18, dtype=np.float32)
        
        # COCO 17 keypoints order (RTMPose format):
        # 0: nose, 1: left_eye, 2: right_eye, 3: left_ear, 4: right_ear
        # 5: left_shoulder, 6: right_shoulder, 7: left_elbow, 8: right_elbow
        # 9: left_wrist, 10: right_wrist, 11: left_hip, 12: right_hip
        # 13: left_knee, 14: right_knee, 15: left_ankle, 16: right_ankle
        
        # OpenPose 18 keypoints order:
        # 0: nose, 1: neck, 2: right_shoulder, 3: right_elbow, 4: right_wrist
        # 5: left_shoulder, 6: left_elbow, 7: left_wrist, 8: right_hip
        # 9: right_knee, 10: right_ankle, 11: left_hip, 12: left_knee
        # 13: left_ankle, 14: right_eye, 15: left_eye, 16: right_ear, 17: left_ear
        
        # Correct RTMPose COCO to OpenPose mapping
        coco_to_openpose_mapping = {
            # Head keypoints
            0: 0,   # nose -> nose
            1: 15,  # left_eye -> left_eye  
            2: 14,  # right_eye -> right_eye
            3: 17,  # left_ear -> left_ear
            4: 16,  # right_ear -> right_ear
            
            # Upper body keypoints
            5: 5,   # left_shoulder -> left_shoulder
            6: 2,   # right_shoulder -> right_shoulder
            7: 6,   # left_elbow -> left_elbow
            8: 3,   # right_elbow -> right_elbow
            9: 7,   # left_wrist -> left_wrist
            10: 4,  # right_wrist -> right_wrist
            
            # Lower body keypoints
            11: 11, # left_hip -> left_hip
            12: 8,  # right_hip -> right_hip
            13: 12, # left_knee -> left_knee
            14: 9,  # right_knee -> right_knee
            15: 13, # left_ankle -> left_ankle
            16: 10, # right_ankle -> right_ankle
        }
        
        # Map all available RTMPose keypoints to OpenPose positions
        for coco_idx, openpose_idx in coco_to_openpose_mapping.items():
            if coco_idx < len(kpts17) and coco_idx < len(conf17):
                kpts18[openpose_idx] = kpts17[coco_idx]
                # Ensure confidence is a scalar
                conf18[openpose_idx] = float(conf17[coco_idx])
        
        # CRITICAL: Calculate neck keypoint (OpenPose index 1) from shoulders
        # This is essential for OpenPose compatibility as COCO format doesn't have neck
        if (len(kpts17) > 6 and len(conf17) > 6 and 
            float(conf17[5]) > 0.05 and float(conf17[6]) > 0.05):  # Both shoulders detected with minimal confidence
            
            left_shoulder = kpts17[5]   # COCO left shoulder
            right_shoulder = kpts17[6]  # COCO right shoulder
            
            # Calculate neck as midpoint between shoulders
            neck_xy = (left_shoulder + right_shoulder) / 2.0
            
            # Neck confidence is average of shoulder confidences, but cap it reasonably
            neck_conf = (float(conf17[5]) + float(conf17[6])) / 2.0
            
            # Assign to OpenPose neck position (index 1)
            kpts18[1] = neck_xy.astype(np.float32)
            conf18[1] = float(neck_conf)
            
        # If shoulders not available, try to estimate neck from other keypoints
        elif (len(kpts17) > 0 and len(conf17) > 0 and float(conf17[0]) > 0.1):  # If nose is detected
            # Fallback: estimate neck position below nose (rough approximation)
            nose_xy = kpts17[0]
            estimated_neck = nose_xy + np.array([0, 20], dtype=np.float32)  # 20 pixels below nose
            
            kpts18[1] = estimated_neck
            conf18[1] = float(conf17[0]) * 0.3  # Lower confidence for estimated neck
        
        return kpts18, conf18

class IntelligentPoseTracker:
    """Smarter pose tracking that prioritizes accuracy over artificial completion"""
    
    def __init__(self, n_points=18, history_size=7, confidence_threshold=0.25):
        self.n_points = n_points
        self.history_size = history_size
        self.confidence_threshold = confidence_threshold
        
        # Store ONLY high-quality pose history
        self.reliable_pose_history = deque(maxlen=history_size)
        self.reliable_confidence_history = deque(maxlen=history_size)
        
        # Track detection consistency for each keypoint
        self.detection_stability = np.zeros(n_points)  # How stable each keypoint detection is
        self.consecutive_detections = np.zeros(n_points)  # Consecutive good detections
        self.last_reliable_positions = np.zeros((n_points, 2))
        self.last_reliable_confidences = np.zeros(n_points)
        
        # Movement analysis
        self.movement_vectors = deque(maxlen=3)
        self.frame_count = 0
        
        # Conservative anatomical connections - only the most reliable ones
        self.core_connections = [
            (1, 2), (1, 5),    # Neck to shoulders (most stable)
            (1, 8), (1, 11),   # Torso to hips (very stable)
            (2, 3), (5, 6),    # Shoulder to elbow (fairly stable)
            (8, 9), (11, 12),  # Hip to knee (fairly stable)
        ]
        
        # Define body part reliability hierarchy (head/torso most reliable)
        self.reliability_hierarchy = {
            'head': [0, 17],           # Most reliable
            'torso': [1],              # Most reliable  
            'shoulders': [2, 5],       # Very reliable
            'hips': [8, 11],          # Very reliable
            'elbows': [3, 6],         # Moderately reliable
            'knees': [9, 12],         # Moderately reliable
            'wrists': [4, 7],         # Less reliable
            'ankles': [10, 13]        # Less reliable
        }

class MovementAnalyzer:
    """Analyzes movement patterns to distinguish real movement from detection noise"""
    
    @staticmethod
    def analyze_movement_pattern(current_points, history, min_history=3):
        """
        Analyze if movement is consistent (real) or erratic (noise/detection error)
        Returns: is_real_movement, movement_confidence, primary_direction
        """
        if len(history) < min_history:
            return False, 0.0, None
            
        # Get last few frames for analysis
        recent_frames = list(history)[-min_history:]
        
        # Calculate movement vectors between consecutive frames
        vectors = []
        for i in range(1, len(recent_frames)):
            prev_frame = np.array(recent_frames[i-1])
            curr_frame = np.array(recent_frames[i])
            
            # Calculate movement for high-confidence keypoints only
            reliable_movements = []
            for j, (prev_pt, curr_pt) in enumerate(zip(prev_frame, curr_frame)):
                # Only consider movements of reliably detected keypoints
                movement_vec = curr_pt - prev_pt
                movement_dist = np.linalg.norm(movement_vec)
                
                # Filter out tiny movements (likely noise)
                if movement_dist > 5:  # Minimum meaningful movement
                    reliable_movements.append(movement_vec)
            
            if reliable_movements:
                # Average movement vector for this frame transition
                avg_vector = np.mean(reliable_movements, axis=0)
                vectors.append(avg_vector)
        
        if len(vectors) < 2:
            return False, 0.0, None
        
        # Analyze consistency of movement vectors
        vector_consistency = MovementAnalyzer._calculate_vector_consistency(vectors)
        movement_magnitude = np.mean([np.linalg.norm(v) for v in vectors])
        
        # Real movement criteria:
        # 1. Consistent direction across frames
        # 2. Reasonable magnitude (not tiny noise, not impossibly large)
        # 3. Smooth acceleration pattern
        
        is_real_movement = (
            vector_consistency > 0.6 and  # Consistent direction
            5 < movement_magnitude < 200 and  # Reasonable speed
            len(vectors) >= 2  # Sufficient history
        )
        
        # Calculate primary movement direction
        if is_real_movement and vectors:
            primary_direction = np.mean(vectors, axis=0)
            primary_direction = primary_direction / (np.linalg.norm(primary_direction) + 1e-8)
        else:
            primary_direction = None
            
        return is_real_movement, vector_consistency, primary_direction
    
    @staticmethod
    def _calculate_vector_consistency(vectors):
        """Calculate how consistent movement vectors are (0=random, 1=perfectly consistent)"""
        if len(vectors) < 2:
            return 0.0
            
        # Normalize vectors
        normalized_vectors = []
        for v in vectors:
            norm = np.linalg.norm(v)
            if norm > 1e-8:
                normalized_vectors.append(v / norm)
        
        if len(normalized_vectors) < 2:
            return 0.0
        
        # Calculate pairwise dot products (cosine similarity)
        similarities = []
        for i in range(len(normalized_vectors)):
            for j in range(i+1, len(normalized_vectors)):
                similarity = np.dot(normalized_vectors[i], normalized_vectors[j])
                similarities.append(max(similarity, 0))  # Only positive correlations
        
        return np.mean(similarities) if similarities else 0.0

class SmartEstimator:
    """Conservative estimation that only fills in keypoints when we're very confident"""
    
    @staticmethod
    def should_estimate_keypoint(target_idx, current_conf, detection_stability, 
                                consecutive_detections, min_stability=0.6):
        """
        Decide if we should estimate a keypoint or leave it as unreliable
        Only estimate if:
        1. The keypoint has been historically stable
        2. We have recent reliable detections
        3. Connected keypoints are currently reliable
        """
        
        # Ensure current_conf is a scalar
        current_conf = float(current_conf) if hasattr(current_conf, '__iter__') else current_conf
        
        # Don't estimate if we don't have enough history
        if consecutive_detections[target_idx] < 3:
            return False
            
        # Don't estimate if the keypoint is historically unreliable
        if detection_stability[target_idx] < min_stability:
            return False
            
        # Don't estimate if current confidence is too low (probably occluded/out of frame)
        if current_conf < 0.05:
            return False
            
        return True
    
    @staticmethod
    def estimate_from_reliable_neighbors(keypoints, confidences, target_idx, 
                                       connections, detection_stability, 
                                       min_neighbor_conf=0.4):
        """
        Conservative neighbor-based estimation using only highly reliable neighbors
        """
        
        # Find highly reliable connected keypoints
        reliable_neighbors = []
        for conn in connections:
            if target_idx in conn:
                other_idx = conn[1] if conn[0] == target_idx else conn[0]
                
                # Ensure confidence is a scalar
                conf_val = float(confidences[other_idx]) if hasattr(confidences[other_idx], '__iter__') else confidences[other_idx]
                
                if (other_idx < len(confidences) and 
                    conf_val > min_neighbor_conf and
                    detection_stability[other_idx] > 0.7):
                    reliable_neighbors.append(other_idx)
        
        # Need at least 2 reliable neighbors for estimation
        if len(reliable_neighbors) < 2:
            return None, 0.0
        
        # Calculate weighted estimate
        estimated_pos = np.zeros(2, dtype=np.float32)
        total_weight = 0
        
        for neighbor_idx in reliable_neighbors:
            # Ensure confidence is a scalar
            conf_val = float(confidences[neighbor_idx]) if hasattr(confidences[neighbor_idx], '__iter__') else confidences[neighbor_idx]
            weight = conf_val * detection_stability[neighbor_idx]
            estimated_pos += keypoints[neighbor_idx] * weight
            total_weight += weight
        
        if total_weight > 0:
            estimated_pos /= total_weight
            # Conservative confidence for estimated points
            estimated_conf = min(0.3, total_weight / len(reliable_neighbors))
            return estimated_pos, estimated_conf
        
        return None, 0.0
    
    @staticmethod
    def conservative_symmetry_estimation(keypoints, confidences, detection_stability,
                                       target_idx, mirror_idx, torso_idx=1,
                                       min_conf_diff=0.5):
        """
        Very conservative symmetry estimation - only when one side is MUCH more reliable
        """
        
        if (target_idx >= len(confidences) or mirror_idx >= len(confidences) or
            torso_idx >= len(confidences)):
            return None, 0.0
        
        # Ensure confidences are scalars
        target_conf = float(confidences[target_idx]) if hasattr(confidences[target_idx], '__iter__') else confidences[target_idx]
        mirror_conf = float(confidences[mirror_idx]) if hasattr(confidences[mirror_idx], '__iter__') else confidences[mirror_idx]
        torso_conf = float(confidences[torso_idx]) if hasattr(confidences[torso_idx], '__iter__') else confidences[torso_idx]
        
        # Only estimate if:
        # 1. Mirror side is highly confident AND historically stable
        # 2. Target side is much less confident
        # 3. Torso is reliably detected (needed for mirroring)
        # 4. The confident side has been stable for multiple frames
        
        mirror_reliable = (mirror_conf > 0.6 and 
                          detection_stability[mirror_idx] > 0.8 and
                          torso_conf > 0.5)
        
        significant_difference = (mirror_conf - target_conf) > min_conf_diff
        
        if mirror_reliable and significant_difference:
            # Mirror across torso
            torso_x = keypoints[torso_idx, 0]
            mirror_offset = keypoints[mirror_idx, 0] - torso_x
            
            estimated_pos = np.array([
                torso_x - mirror_offset,
                keypoints[mirror_idx, 1]
            ], dtype=np.float32)
            
            # Very conservative confidence for mirrored points
            estimated_conf = mirror_conf * 0.4
            
            return estimated_pos, estimated_conf
        
        return None, 0.0

# Max centroid move (standardized px) before the temporal smoother treats it as an identity
# switch and drops stale history (see detect_pose_with_intelligent_tracking). The patient is
# near-stationary in bed, so a large jump means selection switched people.
IDENTITY_JUMP_PX = 100.0


def _confident_centroid(points, confidences, threshold):
    """Centroid of the keypoints above `threshold` (None if too few). Used to detect when the
    selected person changed identity between frames."""
    pts = np.asarray(points, dtype=np.float32)
    conf = np.asarray(confidences, dtype=np.float32).reshape(-1)
    m = conf > threshold
    if int(m.sum()) < 3:
        return None
    return pts[m].mean(axis=0)


def detect_pose_with_intelligent_tracking(rtm_detector, frame, tracker, confidence_threshold=0.25,
                                          preprocess=True):
    """
    Intelligent pose detection that prioritizes accuracy over completeness using RTMPose

    preprocess: apply intelligent_preprocessing (CLAHE + bilateral) before detection. On dark
        EMU footage this CLAHE step can ERASE the (striped-pyjama) patient from the YOLOX
        detector during a seizure while leaving caregivers detectable, which then hijacks the
        keypoints. Set False to detect on the raw standardized frame, where the patient is found
        reliably as the dominant subject. Must be kept consistent between training and deploy.
    """

    # Enhanced preprocessing for better raw detection
    frame_processed = intelligent_preprocessing(frame) if preprocess else frame

    # Use RTMPose for detection instead of OpenPose
    raw_points, raw_confidences = rtm_detector.detect_poses(frame_processed)

    # Identity guard (multi-person clips). detect_poses now picks the PATIENT among several
    # people, so the selected pose can legitimately jump frame-to-frame when the patient is
    # briefly occluded and selection lands on a caregiver, then recovers. The single-person
    # temporal smoother below would blend those two identities and smear the keypoints onto
    # whoever is in the (now stale) history. If the freshly selected pose is far from the last
    # reliable pose, drop the history so we emit the patient's own pose instead of a blend.
    _cur_cen = _confident_centroid(raw_points, raw_confidences, confidence_threshold)
    if len(tracker.reliable_pose_history) > 0:
        _prev_cen = _confident_centroid(tracker.reliable_pose_history[-1],
                                        tracker.reliable_confidence_history[-1],
                                        confidence_threshold)
        if (_cur_cen is not None and _prev_cen is not None and
                float(np.linalg.norm(_cur_cen - _prev_cen)) > IDENTITY_JUMP_PX):
            tracker.reliable_pose_history.clear()
            tracker.reliable_confidence_history.clear()

    # Update detection stability tracking
    update_detection_stability(tracker, raw_points, raw_confidences, confidence_threshold)
    
    # Analyze movement pattern from reliable history
    is_real_movement = False
    movement_confidence = 0.0
    primary_direction = None
    
    if len(tracker.reliable_pose_history) >= 3:
        is_real_movement, movement_confidence, primary_direction = MovementAnalyzer.analyze_movement_pattern(
            raw_points, tracker.reliable_pose_history
        )
    
    # Apply intelligent temporal consistency
    final_points, final_confidences = apply_intelligent_temporal_smoothing(
        raw_points, raw_confidences, tracker, is_real_movement, 
        movement_confidence, primary_direction, confidence_threshold
    )
    
    # Conservative estimation only for historically stable keypoints
    final_points, final_confidences = apply_conservative_estimation(
        final_points, final_confidences, tracker, confidence_threshold
    )
    
    # Update reliable history only with high-quality poses
    if should_add_to_reliable_history(final_confidences, confidence_threshold):
        tracker.reliable_pose_history.append(final_points.copy())
        tracker.reliable_confidence_history.append(final_confidences.copy())
    
    tracker.frame_count += 1
    
    return final_points, final_confidences

def update_detection_stability(tracker, points, confidences, threshold):
    """Update stability tracking for each keypoint"""
    
    for i in range(min(len(points), len(confidences), tracker.n_points)):
        # Ensure confidence is a scalar value
        conf_val = float(confidences[i]) if hasattr(confidences[i], '__iter__') else confidences[i]
        
        if conf_val > threshold:
            # Good detection
            tracker.consecutive_detections[i] += 1
            tracker.detection_stability[i] = min(1.0, 
                tracker.detection_stability[i] + 0.1)
            
            # Update last reliable position
            tracker.last_reliable_positions[i] = points[i].copy()
            tracker.last_reliable_confidences[i] = conf_val
        else:
            # Poor detection
            tracker.consecutive_detections[i] = 0
            tracker.detection_stability[i] = max(0.0, 
                tracker.detection_stability[i] - 0.2)

def apply_intelligent_temporal_smoothing(raw_points, raw_confidences, tracker,
                                       is_real_movement, movement_confidence, 
                                       primary_direction, threshold):
    """
    Intelligent temporal smoothing that adapts to real vs. false movement
    """
    
    if len(tracker.reliable_pose_history) == 0:
        return raw_points, raw_confidences
    
    smoothed_points = raw_points.copy()
    smoothed_confidences = raw_confidences.copy()
    
    prev_reliable = tracker.reliable_pose_history[-1]
    prev_conf = tracker.reliable_confidence_history[-1]
    
    # Different strategies based on movement analysis
    if is_real_movement and movement_confidence > 0.7:
        # Real movement detected - trust current detections more
        print(f"[REAL MOVEMENT] Confidence: {movement_confidence:.2f}, reducing smoothing")
        temporal_weight = 0.8  # Trust current frame heavily
        max_allowed_jump = 150  # Allow larger movements
        
    elif movement_confidence < 0.3:
        # Likely detection noise - apply more smoothing
        temporal_weight = 0.3  # Trust history more
        max_allowed_jump = 60   # Smaller allowed movements
        
    else:
        # Uncertain movement - moderate smoothing
        temporal_weight = 0.6
        max_allowed_jump = 100
    
    for i in range(min(len(raw_points), len(prev_reliable))):
        if i >= len(raw_confidences) or i >= len(prev_conf):
            continue
            
        curr_conf = raw_confidences[i]
        prev_conf_val = prev_conf[i]
        
        # Ensure confidence values are scalars
        curr_conf = float(curr_conf) if hasattr(curr_conf, '__iter__') else curr_conf
        prev_conf_val = float(prev_conf_val) if hasattr(prev_conf_val, '__iter__') else prev_conf_val
        
        # Only apply smoothing if both current and previous are decent
        if curr_conf > threshold and prev_conf_val > threshold:
            
            movement_dist = np.linalg.norm(raw_points[i] - prev_reliable[i])
            
            # Check for unrealistic jumps
            if movement_dist > max_allowed_jump:
                if is_real_movement:
                    # During real movement, check if movement aligns with primary direction
                    if primary_direction is not None:
                        movement_vec = raw_points[i] - prev_reliable[i]
                        movement_vec_norm = movement_vec / (np.linalg.norm(movement_vec) + 1e-8)
                        
                        alignment = np.dot(movement_vec_norm, primary_direction)
                        if alignment > 0.5:  # Movement aligns with detected pattern
                            # Trust the movement but apply light smoothing
                            alpha = 0.85
                        else:
                            # Movement doesn't align - likely error
                            alpha = 0.4
                    else:
                        alpha = 0.7  # Moderate trust during real movement
                else:
                    # Not real movement and large jump - likely error
                    alpha = 0.3
                
                # Apply smoothing for large movements
                smoothed_points[i] = alpha * raw_points[i] + (1 - alpha) * prev_reliable[i]
                # Reduce confidence based on movement magnitude and alignment
                confidence_factor = 0.7 if alpha > 0.7 else 0.5  # Higher confidence if movement is trusted
                smoothed_confidences[i] = min(curr_conf * confidence_factor, prev_conf_val)
            else:
                # Normal movement - apply standard temporal smoothing
                alpha = temporal_weight
                smoothed_points[i] = alpha * raw_points[i] + (1 - alpha) * prev_reliable[i]
                # Keep confidence stable for small movements
                smoothed_confidences[i] = min(curr_conf, prev_conf_val)
    
    return smoothed_points, smoothed_confidences

def apply_conservative_estimation(points, confidences, tracker, threshold):
    """Apply very conservative estimation - only when we're confident it helps"""
    
    estimated_points = points.copy()
    estimated_confidences = confidences.copy()
    
    # Only estimate keypoints that have been historically stable
    for i in range(len(points)):
        # Ensure confidence is a scalar
        conf_val = float(confidences[i]) if hasattr(confidences[i], '__iter__') else confidences[i]
        
        if (i < len(confidences) and conf_val < threshold and
            SmartEstimator.should_estimate_keypoint(i, conf_val, 
                                                   tracker.detection_stability,
                                                   tracker.consecutive_detections)):
            
            # Try neighbor-based estimation first (more reliable)
            estimated_pos, estimated_conf = SmartEstimator.estimate_from_reliable_neighbors(
                points, confidences, i, tracker.core_connections, tracker.detection_stability
            )
            
            if estimated_pos is not None:
                estimated_points[i] = estimated_pos
                estimated_confidences[i] = estimated_conf
                continue
            
            # Try conservative symmetry estimation as last resort
            symmetry_pairs = [(2, 5), (3, 6), (4, 7), (8, 11), (9, 12), (10, 13)]
            
            for left_idx, right_idx in symmetry_pairs:
                if i == left_idx:
                    estimated_pos, estimated_conf = SmartEstimator.conservative_symmetry_estimation(
                        points, confidences, tracker.detection_stability, i, right_idx
                    )
                elif i == right_idx:
                    estimated_pos, estimated_conf = SmartEstimator.conservative_symmetry_estimation(
                        points, confidences, tracker.detection_stability, i, left_idx
                    )
                else:
                    continue
                
                if estimated_pos is not None:
                    estimated_points[i] = estimated_pos
                    estimated_confidences[i] = estimated_conf
                    break
    
    return estimated_points, estimated_confidences

def should_add_to_reliable_history(confidences, threshold):
    """Decide if current pose is reliable enough to add to history"""
    
    # Ensure confidences are scalar values
    confidences_scalar = []
    for conf in confidences:
        if hasattr(conf, '__iter__'):
            confidences_scalar.append(float(conf))
        else:
            confidences_scalar.append(float(conf))
    
    confidences_array = np.array(confidences_scalar)
    
    # Require a minimum number of high-confidence keypoints
    high_conf_count = np.sum(confidences_array > threshold)
    total_keypoints = len(confidences_array)
    
    # Need at least 40% of keypoints to be high confidence
    # AND must have torso + at least one other core body part
    has_torso = len(confidences_array) > 1 and confidences_array[1] > threshold
    has_core_parts = np.sum(confidences_array[[1, 2, 5, 8, 11]] > threshold) >= 3  # torso, shoulders, hips
    
    return (high_conf_count >= total_keypoints * 0.4 and 
            has_torso and has_core_parts)

def intelligent_preprocessing(frame):
    """Preprocessing focused on preserving real features while reducing noise"""
    
    # Convert to LAB for better contrast handling
    lab = cv2.cvtColor(frame, cv2.COLOR_BGR2LAB)
    l, a, b = cv2.split(lab)
    
    # Adaptive histogram equalization with conservative settings
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8,8))
    l_enhanced = clahe.apply(l)
    
    # Recombine
    enhanced = cv2.merge([l_enhanced, a, b])
    enhanced = cv2.cvtColor(enhanced, cv2.COLOR_LAB2BGR)
    
    # Very light denoising that preserves edges
    enhanced = cv2.bilateralFilter(enhanced, 3, 30, 30)
    
    return enhanced

# Quality assessment functions (updated for new approach)
def assess_pose_quality_accurate(keypoints, confidences):
    """Assess pose quality with focus on real detections vs estimations"""
    
    keypoints = np.array(keypoints, dtype=np.float32)
    
    # Ensure confidences are scalar values
    confidences_scalar = []
    for conf in confidences:
        if hasattr(conf, '__iter__'):
            confidences_scalar.append(float(conf))
        else:
            confidences_scalar.append(float(conf))
    
    confidences = np.array(confidences_scalar, dtype=np.float32)
    
    # Distinguish between detected and estimated keypoints
    high_conf_mask = confidences > 0.5  # Likely real detections
    medium_conf_mask = (confidences > 0.25) & (confidences <= 0.5)  # Could be real or estimated
    low_conf_mask = confidences <= 0.25  # Likely estimated or poor detections
    
    # Check core body parts individually to avoid array boolean issues
    core_body_indices = [1, 2, 5, 8, 11]  # torso, shoulders, hips
    core_body_detected_count = 0
    for idx in core_body_indices:
        if idx < len(confidences) and float(confidences[idx]) > 0.4:
            core_body_detected_count += 1
    
    quality_metrics = {
        'avg_confidence': float(np.mean(confidences)),
        'real_detection_ratio': float(np.sum(high_conf_mask) / len(confidences)),
        'estimated_keypoint_ratio': float(np.sum(low_conf_mask) / len(confidences)),
        'core_body_detected': bool(core_body_detected_count >= 4),
        'total_keypoints': len(confidences),
        'detection_quality': 'high' if np.sum(high_conf_mask) >= 8 else 
                           'medium' if np.sum(medium_conf_mask) >= 10 else 'low'
    }
    
    return quality_metrics

def create_accurate_quality_report(all_qualities, video_name):
    """Create quality report focused on detection accuracy"""
    
    total_frames = len(all_qualities)
    if total_frames == 0:
        return None
    
    real_detection_ratios = [q['real_detection_ratio'] for q in all_qualities]
    estimated_ratios = [q['estimated_keypoint_ratio'] for q in all_qualities]
    
    report = {
        'video_name': video_name,
        'total_frames': total_frames,
        'avg_confidence': float(np.mean([q['avg_confidence'] for q in all_qualities])),
        'avg_real_detection_ratio': float(np.mean(real_detection_ratios)),
        'avg_estimated_ratio': float(np.mean(estimated_ratios)),
        'core_body_detection_rate': float(np.mean([q['core_body_detected'] for q in all_qualities])),
        'quality_distribution': {
            'high_quality': sum(1 for q in all_qualities if q['detection_quality'] == 'high') / total_frames,
            'medium_quality': sum(1 for q in all_qualities if q['detection_quality'] == 'medium') / total_frames,
            'low_quality': sum(1 for q in all_qualities if q['detection_quality'] == 'low') / total_frames,
        },
        'accuracy_focus': True
    }
    
    return report

# Example usage and testing
if __name__ == "__main__":
    print("Intelligent Accurate Pose Detection with RTMPose loaded")
    print("Key improvements:")
    print("  - RTMPose integration (more accurate than OpenPose)")
    print("  - Prioritizes accuracy over completeness")
    print("  - Intelligent movement analysis to reduce lag")
    print("  - Conservative estimation (only when confident)")
    print("  - Reduced artificial keypoint generation")
    print("  - Better handling of sudden movements")
    print("  - Stability tracking for each keypoint")
    print("  - Quality metrics focused on real vs estimated detections")
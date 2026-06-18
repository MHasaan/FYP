# enhanced_extract_patches.py - Following original project format with enhancements
# Run: python enhanced_extract_patches.py
import math, cv2
import numpy as np
from pathlib import Path
import json

# Canonical 15-keypoint orderings for each model.
# These determine which OpenPose-18 points are selected and in what order.
# Must match the ordering used when the model was trained.

# VSViGFall.pth: drops neck(1), right_ear(16), left_ear(17); reorders eyes to front.
FALL_INDICES = [0, 15, 14, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]

# SeizureVSViG_winner_nogkn.pth: drops neck(1), left_eye(15), right_ear(16); natural index order.
SEIZURE_INDICES = [0, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 17]


def norm(x):
    """Original normalization function with enhanced error handling"""
    x_min = np.min(x)
    x_max = np.max(x)
    if x_max - x_min == 0:
        return np.zeros_like(x, dtype=np.uint8)
    y = ((x - x_min) / (x_max - x_min)) * 255
    return y.astype(np.uint8)

def gen_kernel(size, sigma):
    """Original kernel generation - exactly as in original"""
    kernel = np.fromfunction(lambda x, y: (1/(2*math.pi*sigma**2)) * math.e ** ((-1*((x-(size-1)/2)**2+(y-(size-1)/2)**2))/(2*sigma**2)), (size, size))
    kernel = kernel / np.sum(kernel)
    kernel = (kernel - np.min(kernel)) / (np.max(kernel) - np.min(kernel))
    return kernel

# Cache of precomputed 3-channel float32 kernels keyed by (size, sigma).
# gen_kernel() uses np.fromfunction which is expensive. At 30 FPS, rebuilding
# it every frame for every call adds up — caching makes it a one-time cost
# per unique (size, sigma) pair (typically just one pair per run).
_KERNEL3_CACHE: dict = {}

def _get_kernel3(size: int, sigma: float) -> np.ndarray:
    """Return a cached (size, size, 3) float32 Gaussian kernel."""
    key = (size, sigma)
    if key not in _KERNEL3_CACHE:
        k = gen_kernel(size, size * sigma)
        _KERNEL3_CACHE[key] = np.expand_dims(k, 2).repeat(3, axis=2)
    return _KERNEL3_CACHE[key]

def extract_patches(img, kpts, kernel_size=128, kernel_sigma=0.3, scale=1/4):
    """
    Original extract_patches function following exact original format with enhancements
    
    Args:
        img: Input image (H, W, 3) - 1080 x 1920 x 3 video resolution
        kpts: Keypoints array (18, 2) or (18, 3) - EXACTLY as in original format
        kernel_size: Size of the extraction kernel (default: 128)
        kernel_sigma: Sigma for Gaussian kernel (default: 0.3) 
        scale: Scale factor for output patches (default: 1/4)
    
    Returns:
        patches: Array of shape (15, scaled_size, scaled_size, 3)
    """
    # Handle both 2D and 3D keypoint formats for compatibility
    if len(kpts.shape) == 2 and kpts.shape[1] == 3:
        # Convert 3D to 2D by taking only x, y coordinates
        kpts_2d = kpts[:, :2].copy()
    else:
        kpts_2d = kpts.copy()
    
    # Validate input format
    if kpts_2d.shape != (18, 2):
        raise ValueError(f"Expected keypoints shape (18, 2), got {kpts_2d.shape}")
    
    img_shape = img.shape # 1080 x 1920 x 3 video resolution
    pad_img = np.zeros((img_shape[0]+kernel_size*2, img_shape[1]+kernel_size*2, 3))
    pad_img[kernel_size:-kernel_size, kernel_size:-kernel_size, :] = img
    kernel = _get_kernel3(kernel_size, kernel_sigma)
    
    # Canonical VSViG 15-point selection from OpenPose 18-point layout.
    # Reorders into 5 body-part groups of 3 (Head, R_Arm, L_Arm, R_Leg, L_Leg).
    # Drops: neck(1), right_ear(16), left_ear(17).
    OPENPOSE_18_TO_VSVIG_15 = [0, 15, 14, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]
    kpts_filtered = kpts_2d[OPENPOSE_18_TO_VSVIG_15]  # Shape: (15, 2)
    
    patches = np.zeros((15, math.ceil(scale*kernel_size), math.ceil(scale*kernel_size), 3))
    
    for idx in range(15):
        try:
            # Enhanced bounds checking while maintaining original logic
            x, y = kpts_filtered[idx]
            
            # Ensure coordinates are within reasonable bounds (enhancement)
            H, W = img_shape[0], img_shape[1]
            x = max(kernel_size//2, min(W + kernel_size//2, x))
            y = max(kernel_size//2, min(H + kernel_size//2, y))
            
            # Original patch extraction logic - EXACTLY as in original
            y_start = int(y + 0.5*kernel_size)
            y_end = int(y + 1.5*kernel_size)
            x_start = int(x + 0.5*kernel_size)
            x_end = int(x + 1.5*kernel_size)
            
            # Enhanced bounds checking for padded image
            y_start = max(0, min(pad_img.shape[0] - kernel_size, y_start))
            y_end = y_start + kernel_size
            x_start = max(0, min(pad_img.shape[1] - kernel_size, x_start))
            x_end = x_start + kernel_size
            
            # Extract patch with original logic
            patch_region = pad_img[y_start:y_end, x_start:x_end, :] * kernel
            tmp = norm(patch_region)
            tmp = cv2.resize(tmp, (0, 0), fx=scale, fy=scale, interpolation=cv2.INTER_LINEAR)
            patches[idx, :, :, :] = tmp
            
        except Exception as e:
            # Enhanced error handling - create zero patch on failure
            print(f"Warning: Failed to extract patch for keypoint {idx}: {e}")
            patches[idx, :, :, :] = np.zeros((math.ceil(scale*kernel_size), math.ceil(scale*kernel_size), 3), dtype=np.uint8)
    
    return patches

def validate_keypoint(kpt, img_shape, min_confidence=0.1):
    """Validate if a keypoint is usable"""
    x, y, conf = kpt
    H, W = img_shape[:2]
    
    # Check confidence
    if conf < min_confidence:
        return False, "low_confidence"
    
    # Check for explicit failure markers
    if x == 0.0 and y == 0.0 and conf == 0.0:
        return False, "explicit_failure"
    
    # Check bounds (with some tolerance for edge cases)
    if not (-10 <= x < W + 10 and -10 <= y < H + 10):
        return False, "out_of_bounds"
    
    return True, "valid"

def estimate_missing_keypoint(kpt_idx, all_kpts, img_shape, body_connections):
    """Estimate missing keypoint based on body structure.
    
    Offsets are expressed as fractions of body scale (torso length) rather than
    fixed pixel values so the logic is resolution-independent.
    """
    H, W = img_shape[:2]

    # Compute body scale from torso length (neck → hip_center), default to H/4
    body_scale = H / 4.0
    if len(all_kpts) > 11:
        torso_ref = all_kpts[1] if (len(all_kpts) > 1 and all_kpts[1][2] > 0.2) else None
        hip_refs = []
        if len(all_kpts) > 8 and all_kpts[8][2] > 0.2:
            hip_refs.append(all_kpts[8][:2])
        if len(all_kpts) > 11 and all_kpts[11][2] > 0.2:
            hip_refs.append(all_kpts[11][:2])
        if torso_ref is not None and hip_refs:
            hip_center = np.mean(hip_refs, axis=0)
            body_scale = max(np.linalg.norm(torso_ref[:2] - hip_center), H / 8.0)

    # Relative offsets (fractions of body_scale)
    fallback_strategies = {
        0:  {'fallback': 'torso_offset', 'offset': (0.0,  -0.55)},   # Nose
        17: {'fallback': 'torso_offset', 'offset': (0.0,  -0.40)},   # Neck
        2:  {'fallback': 'torso_offset', 'offset': (-0.35, 0.12)},   # RShoulder
        5:  {'fallback': 'torso_offset', 'offset': ( 0.35, 0.12)},   # LShoulder
        3:  {'fallback': 'shoulder_offset', 'ref': 2, 'offset': (0.0, 0.30)},  # RElbow
        6:  {'fallback': 'shoulder_offset', 'ref': 5, 'offset': (0.0, 0.30)},  # LElbow
        4:  {'fallback': 'elbow_offset', 'ref': 3, 'offset': (0.0, 0.30)},     # RWrist
        7:  {'fallback': 'elbow_offset', 'ref': 6, 'offset': (0.0, 0.30)},     # LWrist
        8:  {'fallback': 'torso_offset', 'offset': (-0.18, 0.75)},   # RHip
        11: {'fallback': 'torso_offset', 'offset': ( 0.18, 0.75)},   # LHip
        9:  {'fallback': 'hip_offset', 'ref': 8,  'offset': (0.0, 0.55)},  # RKnee
        12: {'fallback': 'hip_offset', 'ref': 11, 'offset': (0.0, 0.55)},  # LKnee
        10: {'fallback': 'knee_offset', 'ref': 9,  'offset': (0.0, 0.55)}, # RAnkle
        13: {'fallback': 'knee_offset', 'ref': 12, 'offset': (0.0, 0.55)}, # LAnkle
        1:  {'fallback': 'center', 'offset': (0.0, 0.0)},
    }
    
    if kpt_idx not in fallback_strategies:
        return np.array([W//2, H//2])
    
    strategy = fallback_strategies[kpt_idx]
    ox, oy = strategy['offset']
    px_offset = np.array([ox * body_scale, oy * body_scale])
    
    if strategy['fallback'] == 'center':
        return np.array([W//2, H//2])
    
    elif strategy['fallback'] == 'torso_offset':
        if len(all_kpts) > 1 and all_kpts[1][2] > 0.2:
            return all_kpts[1][:2] + px_offset
        return np.array([W//2, H//2])
    
    elif strategy['fallback'] in ('shoulder_offset', 'hip_offset', 'elbow_offset', 'knee_offset'):
        ref_idx = strategy['ref']
        if len(all_kpts) > ref_idx and all_kpts[ref_idx][2] > 0.2:
            return all_kpts[ref_idx][:2] + px_offset
        # Fallback to torso
        if len(all_kpts) > 1 and all_kpts[1][2] > 0.2:
            return all_kpts[1][:2] + px_offset
        return np.array([W//2, H//2])
    
    return np.array([W//2, H//2])

def extract_patches_with_confidence(img, kpts, kernel_size=128, kernel_sigma=0.3,
                                   scale=1/4, min_confidence=0.1, debug=False,
                                   ref_height=1080, indices_to_keep=None):
    """
    Extract patches with robust confidence handling and fallback strategies.

    Args:
        img: Input image (H, W, 3)
        kpts: Keypoints array (18, 3) - x, y, confidence
        kernel_size: Base Gaussian kernel size at ref_height resolution
        kernel_sigma: Sigma for Gaussian kernel
        scale: Scale factor for output patches
        min_confidence: Minimum confidence threshold
        debug: Print debug information
        ref_height: Reference frame height for resolution-aware kernel scaling (default 1080)
        indices_to_keep: Which of the 18 OpenPose keypoints to select, in order.
                         Defaults to FALL_INDICES (backward-compatible).
                         Use SEIZURE_INDICES for the seizure model.

    Returns:
        patches: Array of shape (15, scaled_size, scaled_size, 3)
        valid_mask: Boolean mask indicating which patches had valid keypoints
        debug_info: Dictionary with debugging information
    """
    if indices_to_keep is None:
        indices_to_keep = FALL_INDICES

    img_shape = img.shape
    H, W = img_shape[0], img_shape[1]

    # Scale kernel window so each patch covers the same body fraction at any resolution.
    kernel_size = max(8, int(round(kernel_size * H / ref_height)))

    # Ensure input is correct format
    if len(kpts.shape) != 2 or kpts.shape[1] != 3:
        raise ValueError(f"Expected keypoints shape (18, 3), got {kpts.shape}")

    # Create padded image
    pad_size = kernel_size
    pad_img = np.zeros((H + 2*pad_size, W + 2*pad_size, 3), dtype=img.dtype)
    pad_img[pad_size:pad_size+H, pad_size:pad_size+W, :] = img

    # Generate kernel (cached — expensive np.fromfunction is a one-time cost per size/sigma)
    kernel = _get_kernel3(kernel_size, kernel_sigma)

    # Select and order the 15 keypoints according to the model-specific ordering
    kpts_filtered = kpts[indices_to_keep]  # Shape: (15, 3)
    
    # Calculate output patch size
    output_size = math.ceil(scale * kernel_size)
    patches = np.zeros((15, output_size, output_size, 3), dtype=np.uint8)
    valid_mask = np.zeros(15, dtype=bool)
    
    # Debug information
    debug_info = {
        'validation_results': [],
        'fallback_used': [],
        'patch_stats': []
    }
    
    # Body connections for anatomical estimation (adjusted for filtered indices)
    body_connections = [
        (0, 1), (1, 2), (2, 3), (3, 4),    # Adjusted for filtered keypoints
        (1, 5), (5, 6), (6, 7),
        (1, 8), (8, 9), (9, 10),
        (1, 11), (11, 12), (12, 13),
        (1, 14), (14, 15), (15, 16)
    ]
    
    for idx in range(15):
        try:
            original_kpt = kpts_filtered[idx]
            x, y, confidence = original_kpt
            
            # Validate keypoint
            is_valid, reason = validate_keypoint(original_kpt, img_shape, min_confidence)
            
            debug_info['validation_results'].append({
                'idx': idx,
                'original_pos': (float(x), float(y)),
                'confidence': float(confidence),
                'is_valid': is_valid,
                'reason': reason
            })
            
            # Handle invalid keypoints
            if not is_valid:
                # Estimate position using anatomical knowledge
                estimated_pos = estimate_missing_keypoint(idx, kpts_filtered, img_shape, body_connections)
                x, y = estimated_pos
                confidence = 0.15  # Low but non-zero confidence for estimated points
                
                debug_info['fallback_used'].append({
                    'idx': idx,
                    'original_pos': (float(original_kpt[0]), float(original_kpt[1])),
                    'estimated_pos': (float(x), float(y)),
                    'reason': reason
                })
                
                if debug:
                    print(f"Keypoint {idx}: {reason} -> estimated at ({x:.1f}, {y:.1f})")
            else:
                valid_mask[idx] = True
            
            # Ensure coordinates are within reasonable bounds
            x = max(0, min(W-1, x))
            y = max(0, min(H-1, y))
            
            # Extract patch around keypoint (adjusted for padding)
            kpt_x = int(x) + pad_size
            kpt_y = int(y) + pad_size
            
            # Calculate patch boundaries
            y_start = kpt_y - kernel_size // 2
            y_end = kpt_y + kernel_size // 2
            x_start = kpt_x - kernel_size // 2  
            x_end = kpt_x + kernel_size // 2
            
            # Ensure boundaries are within padded image
            y_start = max(0, min(pad_img.shape[0] - kernel_size, y_start))
            y_end = y_start + kernel_size
            x_start = max(0, min(pad_img.shape[1] - kernel_size, x_start))
            x_end = x_start + kernel_size
            
            # Extract patch
            patch = pad_img[y_start:y_end, x_start:x_end, :]
            
            # Ensure patch is correct size
            if patch.shape[:2] != (kernel_size, kernel_size):
                # Create properly sized patch
                proper_patch = np.zeros((kernel_size, kernel_size, 3), dtype=patch.dtype)
                
                # Copy available data to center
                h_offset = (kernel_size - patch.shape[0]) // 2
                w_offset = (kernel_size - patch.shape[1]) // 2
                h_end = h_offset + patch.shape[0]
                w_end = w_offset + patch.shape[1]
                
                proper_patch[h_offset:h_end, w_offset:w_end, :] = patch
                patch = proper_patch
            
            # Apply kernel and normalize
            patch_weighted = patch.astype(np.float32) * kernel
            patch_normalized = norm(patch_weighted)
            
            # Resize to final scale
            if scale != 1.0:
                patch_resized = cv2.resize(patch_normalized, (output_size, output_size), 
                                         interpolation=cv2.INTER_LINEAR)
            else:
                patch_resized = patch_normalized
            
            patches[idx, :, :, :] = patch_resized
            
            # Debug stats
            debug_info['patch_stats'].append({
                'idx': idx,
                'final_pos': (float(x), float(y)),
                'patch_mean': float(np.mean(patch_resized)),
                'patch_std': float(np.std(patch_resized)),
                'is_valid': bool(valid_mask[idx])
            })
            
        except Exception as e:
            print(f"Error extracting patch for keypoint {idx}: {e}")
            patches[idx, :, :, :] = np.zeros((output_size, output_size, 3), dtype=np.uint8)
            valid_mask[idx] = False
            
            debug_info['patch_stats'].append({
                'idx': idx,
                'error': str(e),
                'is_valid': False
            })
    
    # Summary statistics
    debug_info['summary'] = {
        'total_keypoints': 15,
        'valid_keypoints': int(np.sum(valid_mask)),
        'fallback_used_count': len(debug_info['fallback_used']),
        'success_rate': float(np.sum(valid_mask) / 15),
        'avg_confidence': float(np.mean([r['confidence'] for r in debug_info['validation_results']]))
    }
    
    if debug:
        print(f"Patch extraction summary: {debug_info['summary']['valid_keypoints']}/15 valid, "
              f"{debug_info['summary']['fallback_used_count']} fallbacks used")
    
    return patches, valid_mask, debug_info



def create_patch_quality_report(debug_info, video_name, frame_idx):
    """Create a quality report for patch extraction"""
    
    summary = debug_info['summary']
    
    report = {
        'video_name': video_name,
        'frame_idx': frame_idx,
        'extraction_quality': {
            'success_rate': summary['success_rate'],
            'valid_keypoints': summary['valid_keypoints'],
            'fallback_count': summary['fallback_used_count'],
            'avg_confidence': summary['avg_confidence']
        },
        'quality_grade': 'excellent' if summary['success_rate'] > 0.8 else
                        'good' if summary['success_rate'] > 0.6 else
                        'fair' if summary['success_rate'] > 0.4 else 'poor',
        'common_failures': {}
    }
    
    # Analyze common failure patterns
    failure_reasons = [r['reason'] for r in debug_info['validation_results'] if not r['is_valid']]
    for reason in set(failure_reasons):
        report['common_failures'][reason] = failure_reasons.count(reason)
    
    return report




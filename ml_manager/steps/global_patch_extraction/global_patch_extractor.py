# global_patch_extractor.py - Full body global patch extraction for enhanced fall detection
# Run: python global_patch_extractor.py
import cv2
import numpy as np
import math
from pathlib import Path
import torch

def extract_global_patch(
    img,
    kpts,
    target_size=(64, 64),
    padding_ratio=0.2,
    prev_bbox=None,
    ema_alpha=None
):
    """Extract a temporally smoothed, letterboxed global body patch.

    Args:
        img: Input image (H, W, 3) - 1080 x 1920 x 3 video resolution.
        kpts: Keypoints array (18, 3) with confidence [x, y, conf] or (18, 2) [x, y].
        target_size: Output patch size (default: 64x64 for global context).
        padding_ratio: Extra padding around detected body (default: 0.2 = 20%).
        prev_bbox: Previously smoothed bounding box [x_min, y_min, x_max, y_max] for EMA smoothing.
        ema_alpha: Smoothing coefficient for EMA (0=no smoothing, 1=use current box only).

    Returns:
        global_patch: Extracted and resized global patch (target_size[0], target_size[1], 3).
        bbox_info: Bounding box information for debugging (includes raw & smoothed boxes).
    """
    H, W = img.shape[:2]
    
    # Handle both 2D and 3D keypoint formats
    if len(kpts.shape) == 2 and kpts.shape[1] == 3:
        kpts_2d = kpts[:, :2]  # (18, 2) - x, y coordinates
        confidences = kpts[:, 2]  # (18,) - confidence values
    else:
        kpts_2d = kpts.copy()  # Already 2D
        confidences = np.ones(len(kpts_2d))  # Dummy confidences
    
    # Filter valid keypoints (confidence > 0.1 and within image bounds)
    valid_mask = (confidences > 0.1) & \
                 (kpts_2d[:, 0] > 0) & (kpts_2d[:, 0] < W) & \
                 (kpts_2d[:, 1] > 0) & (kpts_2d[:, 1] < H)
    
    valid_kpts = kpts_2d[valid_mask]
    
    if len(valid_kpts) < 3:
        # Not enough valid keypoints - use center region as fallback
        center_x, center_y = W // 2, H // 2
        fallback_size = min(H, W) // 3
        x_min = max(0, center_x - fallback_size // 2)
        x_max = min(W, center_x + fallback_size // 2)
        y_min = max(0, center_y - fallback_size // 2)  
        y_max = min(H, center_y + fallback_size // 2)
        
        bbox_info = {
            'x_min': x_min, 'x_max': x_max,
            'y_min': y_min, 'y_max': y_max,
            'valid_keypoints': len(valid_kpts),
            'method': 'fallback_center'
        }
    else:
        # Calculate bounding box from valid keypoints
        x_min_kpt = np.min(valid_kpts[:, 0])
        x_max_kpt = np.max(valid_kpts[:, 0])
        y_min_kpt = np.min(valid_kpts[:, 1])
        y_max_kpt = np.max(valid_kpts[:, 1])
        
        # Add padding
        width = x_max_kpt - x_min_kpt
        height = y_max_kpt - y_min_kpt
        
        # Ensure minimum size for very compact poses
        min_size = max(height, width, min(H, W) // 6)
        if width < min_size:
            center_x = (x_min_kpt + x_max_kpt) / 2
            x_min_kpt = center_x - min_size / 2
            x_max_kpt = center_x + min_size / 2
            width = min_size
        if height < min_size:
            center_y = (y_min_kpt + y_max_kpt) / 2
            y_min_kpt = center_y - min_size / 2
            y_max_kpt = center_y + min_size / 2
            height = min_size
        
        padding_x = width * padding_ratio
        padding_y = height * padding_ratio
        
        x_min = max(0, int(x_min_kpt - padding_x))
        x_max = min(W, int(x_max_kpt + padding_x))
        y_min = max(0, int(y_min_kpt - padding_y))
        y_max = min(H, int(y_max_kpt + padding_y))
        
        bbox_info = {
            'x_min': x_min, 'x_max': x_max,
            'y_min': y_min, 'y_max': y_max,
            'valid_keypoints': len(valid_kpts),
            'method': 'keypoint_bbox',
            'original_width': width,
            'original_height': height
        }

    # PROBLEM 1 FIX: Temporal Box Smoothing (EMA)
    # Create raw bbox from current frame detection
    raw_bbox = np.array([bbox_info['x_min'], bbox_info['y_min'], bbox_info['x_max'], bbox_info['y_max']], dtype=np.float32)

    # Apply Exponential Moving Average smoothing if we have previous frame data
    smoothed_bbox = raw_bbox.copy()
    if prev_bbox is not None and ema_alpha is not None:
        # ema_alpha = how much weight to give current frame (0=all previous, 1=all current)
        # Typical value: 0.2 means 20% current frame + 80% previous smoothed result
        ema_alpha = float(np.clip(ema_alpha, 0.0, 1.0))
        smoothed_bbox = ema_alpha * raw_bbox + (1.0 - ema_alpha) * prev_bbox

    # Convert smoothed float bbox to integer pixel coordinates
    x_min = int(np.clip(np.floor(smoothed_bbox[0]), 0, W - 1))
    y_min = int(np.clip(np.floor(smoothed_bbox[1]), 0, H - 1))
    x_max = int(np.clip(np.ceil(smoothed_bbox[2]), x_min + 1, W))
    y_max = int(np.clip(np.ceil(smoothed_bbox[3]), y_min + 1, H))

    # Update bounding information post smoothing
    bbox_info.update({
        'x_min': x_min,
        'x_max': x_max,
        'y_min': y_min,
        'y_max': y_max,
        'raw_bbox': raw_bbox.tolist(),
        'smoothed_bbox': smoothed_bbox.tolist(),
        'ema_alpha': ema_alpha
    })
    
    # Extract the region
    global_region = img[y_min:y_max, x_min:x_max, :]

    crop_h, crop_w = global_region.shape[:2]
    if crop_h == 0 or crop_w == 0:
        # Fallback to black patch if crop fails
        bbox_info['method'] = bbox_info.get('method', 'unknown') + '_degenerate'
        global_patch = np.zeros((target_size[0], target_size[1], 3), dtype=np.uint8)
        return global_patch, bbox_info

    # PROBLEM 2 FIX: Square Letterboxed Crops (preserve aspect ratio)
    # Example: 400x800 crop → 800x800 square with black bars → resize to 64x64
    # This prevents distortion: standing person stays tall/thin, fallen person stays wide/short
    square_size = max(crop_h, crop_w)
    square_canvas = np.zeros((square_size, square_size, 3), dtype=global_region.dtype)

    # Center the rectangular crop in the square canvas (adds black letterboxing)
    y_offset = (square_size - crop_h) // 2
    x_offset = (square_size - crop_w) // 2
    square_canvas[y_offset:y_offset + crop_h, x_offset:x_offset + crop_w] = global_region

    # Now resize the square (with letterboxing) to target size
    global_patch = cv2.resize(square_canvas, target_size, interpolation=cv2.INTER_LINEAR)

    bbox_info.update({
        'square_size': square_size,
        'letterboxed': True,
        'x_offset': int(x_offset),
        'y_offset': int(y_offset)
    })
    
    return global_patch, bbox_info

def extract_global_patches_batch(video_frames, keypoints_sequence, target_size=(64, 64), smooth_alpha=0.2):
    """Extract smoothed, letterboxed global patches for an entire video sequence.

    Args:
        video_frames: List of frames or numpy array (T, H, W, 3).
        keypoints_sequence: Keypoints for all frames (T, 18, 3).
        target_size: Output patch size.
        smooth_alpha: EMA coefficient used to stabilise bounding boxes across frames.

    Returns:
        global_patches: Array of global patches (T, target_size[0], target_size[1], 3).
        bbox_infos: List of bounding box information for each frame.
    """
    if isinstance(video_frames, list):
        T = len(video_frames)
    else:
        T = video_frames.shape[0]
    
    global_patches = np.zeros((T, target_size[0], target_size[1], 3), dtype=np.uint8)
    bbox_infos = []
    prev_bbox = None  # Track previous smoothed bbox for EMA
    
    for t in range(T):
        if isinstance(video_frames, list):
            frame = video_frames[t]
        else:
            frame = video_frames[t]
            
        kpts = keypoints_sequence[t]  # (18, 3)
        
        try:
            # Extract with temporal smoothing
            global_patch, bbox_info = extract_global_patch(
                frame,
                kpts,
                target_size=target_size,
                prev_bbox=prev_bbox,  # Pass previous frame's smoothed bbox
                ema_alpha=smooth_alpha,  # Smoothing weight (0.2 = 20% current, 80% previous)
            )
            global_patches[t] = global_patch
            bbox_infos.append(bbox_info)
            
            # Update prev_bbox for next frame
            prev_bbox = np.array(
                bbox_info.get('smoothed_bbox', 
                bbox_info.get('raw_bbox', 
                [bbox_info['x_min'], bbox_info['y_min'], bbox_info['x_max'], bbox_info['y_max']])), 
                dtype=np.float32
            )
        except Exception as e:
            # Fallback: black patch
            global_patches[t] = np.zeros((target_size[0], target_size[1], 3), dtype=np.uint8)
            bbox_infos.append({'error': str(e), 'method': 'failed'})
    
    return global_patches, bbox_infos





def save_global_patches(global_patches, output_path, format='pt'):
    """
    Save global patches to file
    
    Args:
        global_patches: Patches array (T, H, W, 3)
        output_path: Output file path
        format: Save format ('pt' for PyTorch, 'npy' for NumPy)
    """
    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    
    if format == 'pt':
        # Convert to PyTorch tensor and save
        if isinstance(global_patches, np.ndarray):
            global_patches = torch.from_numpy(global_patches)
        
        # Add batch dimension: (1, T, H, W, 3)
        if global_patches.dim() == 4:
            global_patches = global_patches.unsqueeze(0)
        
        torch.save(global_patches, output_path)
    elif format == 'npy':
        if isinstance(global_patches, torch.Tensor):
            global_patches = global_patches.numpy()
        np.save(output_path, global_patches)
    else:
        raise ValueError(f"Unsupported format: {format}")


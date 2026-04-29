# kinematic_features.py - Extract fall-relevant kinematic features from keypoint sequences
# Run: python kinematic_features.py
import numpy as np
import torch
from pathlib import Path
import math

class KinematicFeatureExtractor:
    """Extract kinematic features relevant to fall detection"""
    
    def __init__(self):
        # COCO keypoint indices
        self.keypoint_names = [
            'nose', 'neck', 'right_shoulder', 'right_elbow', 'right_wrist',
            'left_shoulder', 'left_elbow', 'left_wrist', 'right_hip', 'right_knee',
            'right_ankle', 'left_hip', 'left_knee', 'left_ankle', 'right_eye',
            'left_eye', 'right_ear', 'left_ear'
        ]
        
        # Define body part groups for feature extraction
        self.body_parts = {
            'head': [0, 14, 15, 16, 17],  # nose, eyes, ears
            'torso': [1, 2, 5, 8, 11],    # neck, shoulders, hips
            'right_arm': [2, 3, 4],       # right shoulder, elbow, wrist
            'left_arm': [5, 6, 7],        # left shoulder, elbow, wrist
            'right_leg': [8, 9, 10],      # right hip, knee, ankle
            'left_leg': [11, 12, 13],     # left hip, knee, ankle
            'upper_body': [0, 1, 2, 3, 4, 5, 6, 7, 14, 15, 16, 17],
            'lower_body': [8, 9, 10, 11, 12, 13]
        }
        
        # Joint connections for angle calculations
        self.joint_connections = {
            # Upper body angles
            'neck_right_shoulder': ([1], [2]),
            'neck_left_shoulder': ([1], [5]),
            'right_shoulder_elbow': ([2], [3]),
            'left_shoulder_elbow': ([5], [6]),
            'right_elbow_wrist': ([3], [4]),
            'left_elbow_wrist': ([6], [7]),
            
            # Lower body angles
            'right_hip_knee': ([8], [9]),
            'left_hip_knee': ([11], [12]),
            'right_knee_ankle': ([9], [10]),
            'left_knee_ankle': ([12], [13]),
            
            # Torso angles
            'shoulders_line': ([2], [5]),  # Shoulder line angle
            'hips_line': ([8], [11]),      # Hip line angle
            'spine': ([1], [8, 11]),       # Neck to hip center
        }
    
    def compute_center_of_mass(self, kpts_sequence, confidence_threshold=0.1, image_size=None):
        """
        Compute center of mass trajectory
        
        Args:
            kpts_sequence: (T, 18, 3) - [x, y, confidence]
            image_size: (H, W) tuple or None. Used for fallback when no valid keypoints.
        
        Returns:
            com_trajectory: (T, 2) - center of mass x, y coordinates
            com_velocity: (T-1, 2) - velocity of center of mass
            com_acceleration: (T-2, 2) - acceleration of center of mass
        """
        T = kpts_sequence.shape[0]
        com_trajectory = np.zeros((T, 2))

        # Resolution-independent fallback center
        if image_size is not None:
            center_fallback = [image_size[1] / 2.0, image_size[0] / 2.0]  # (cx, cy)
        else:
            # Estimate from the max keypoint coordinate range
            valid = kpts_sequence[:, :, 2] > confidence_threshold
            if valid.any():
                xs = kpts_sequence[:, :, 0][valid]
                ys = kpts_sequence[:, :, 1][valid]
                center_fallback = [(xs.min() + xs.max()) / 2.0, (ys.min() + ys.max()) / 2.0]
            else:
                center_fallback = [0.0, 0.0]
        
        for t in range(T):
            kpts = kpts_sequence[t]  # (18, 3)
            valid_mask = kpts[:, 2] > confidence_threshold
            
            if np.sum(valid_mask) > 0:
                valid_points = kpts[valid_mask, :2]  # (N, 2)
                weights = kpts[valid_mask, 2]  # (N,) - confidence as weight
                
                # Weighted center of mass
                com_x = np.average(valid_points[:, 0], weights=weights)
                com_y = np.average(valid_points[:, 1], weights=weights)
                com_trajectory[t] = [com_x, com_y]
            else:
                # No valid points - use previous or center
                if t > 0:
                    com_trajectory[t] = com_trajectory[t-1]
                else:
                    com_trajectory[t] = center_fallback
        
        # Compute velocity (first derivative)
        com_velocity = np.zeros((T-1, 2))
        for t in range(T-1):
            com_velocity[t] = com_trajectory[t+1] - com_trajectory[t]
        
        # Compute acceleration (second derivative)
        com_acceleration = np.zeros((T-2, 2))
        for t in range(T-2):
            com_acceleration[t] = com_velocity[t+1] - com_velocity[t]
        
        return com_trajectory, com_velocity, com_acceleration
    
    
    def compute_body_orientation(self, kpts_sequence, confidence_threshold=0.1):
        """
        Compute body orientation features (important for fall detection)
        
        Args:
            kpts_sequence: (T, 18, 3)
        
        Returns:
            orientations: Dictionary of orientation features over time
        """
        T = kpts_sequence.shape[0]
        orientations = {
            'shoulder_line_angle': np.zeros(T),  # Shoulder line tilt
            'hip_line_angle': np.zeros(T),       # Hip line tilt
            'spine_angle': np.zeros(T),          # Spine tilt from vertical
            'body_compactness': np.zeros(T),     # How compact the pose is
            'vertical_extent': np.zeros(T),      # Height span of the person
            'horizontal_extent': np.zeros(T),    # Width span of the person
        }
        
        for t in range(T):
            kpts = kpts_sequence[t]  # (18, 3)
            
            # Shoulder line angle
            if (kpts[2, 2] > confidence_threshold and kpts[5, 2] > confidence_threshold):
                shoulder_vec = kpts[5, :2] - kpts[2, :2]  # Left - Right shoulder
                shoulder_angle = np.degrees(np.arctan2(shoulder_vec[1], shoulder_vec[0]))
                orientations['shoulder_line_angle'][t] = shoulder_angle
            
            # Hip line angle
            if (kpts[8, 2] > confidence_threshold and kpts[11, 2] > confidence_threshold):
                hip_vec = kpts[11, :2] - kpts[8, :2]  # Left - Right hip
                hip_angle = np.degrees(np.arctan2(hip_vec[1], hip_vec[0]))
                orientations['hip_line_angle'][t] = hip_angle
            
            # Spine angle (neck to hip center)
            if (kpts[1, 2] > confidence_threshold and 
                kpts[8, 2] > confidence_threshold and kpts[11, 2] > confidence_threshold):
                hip_center = (kpts[8, :2] + kpts[11, :2]) / 2
                spine_vec = kpts[1, :2] - hip_center
                # Angle from vertical (0 degrees = perfectly upright)
                spine_angle = np.degrees(np.arctan2(spine_vec[0], -spine_vec[1]))
                orientations['spine_angle'][t] = spine_angle
            
            # Body compactness and extents
            valid_mask = kpts[:, 2] > confidence_threshold
            if np.sum(valid_mask) > 3:
                valid_points = kpts[valid_mask, :2]
                
                # Compactness: ratio of area to convex hull
                x_span = np.max(valid_points[:, 0]) - np.min(valid_points[:, 0])
                y_span = np.max(valid_points[:, 1]) - np.min(valid_points[:, 1])
                
                orientations['horizontal_extent'][t] = x_span
                orientations['vertical_extent'][t] = y_span
                
                # Compactness as ratio of actual spread to maximum possible
                max_possible_span = max(x_span, y_span)
                if max_possible_span > 0:
                    compactness = min(x_span, y_span) / max_possible_span
                    orientations['body_compactness'][t] = compactness
        
        return orientations

    def compute_joint_velocities(self, kpts_sequence, confidence_threshold=0.1):
        """Compute per-joint velocities and magnitudes across frames.

        Args:
            kpts_sequence: (T, 18, 3) array of keypoints with confidence.

        Returns:
            joint_velocities: (T-1, 18, 2) array of frame-to-frame displacements.
            velocity_magnitudes: (T-1, 18) array of displacement magnitudes.
        """
        T = kpts_sequence.shape[0]
        num_joints = kpts_sequence.shape[1]

        if T < 2:
            return np.zeros((0, num_joints, 2)), np.zeros((0, num_joints))

        joint_velocities = np.zeros((T - 1, num_joints, 2), dtype=np.float32)
        velocity_magnitudes = np.zeros((T - 1, num_joints), dtype=np.float32)

        for t in range(T - 1):
            curr = kpts_sequence[t]
            nxt = kpts_sequence[t + 1]

            valid_curr = curr[:, 2] > confidence_threshold
            valid_next = nxt[:, 2] > confidence_threshold
            valid_mask = valid_curr & valid_next

            if not np.any(valid_mask):
                continue

            displacement = nxt[:, :2] - curr[:, :2]
            joint_velocities[t, valid_mask, :] = displacement[valid_mask]
            velocity_magnitudes[t, valid_mask] = np.linalg.norm(displacement[valid_mask], axis=1)

        return joint_velocities, velocity_magnitudes
    
    def compute_fall_specific_features(self, kpts_sequence, confidence_threshold=0.1):
        """
        Compute features specifically relevant to fall detection
        
        Args:
            kpts_sequence: (T, 18, 3)
        
        Returns:
            fall_features: Dictionary of fall-specific features
        """
        T = kpts_sequence.shape[0]
        
        # Get basic features
        com_traj, com_vel, com_acc = self.compute_center_of_mass(kpts_sequence, confidence_threshold)
        joint_vels, vel_mags = self.compute_joint_velocities(kpts_sequence, confidence_threshold)
        orientations = self.compute_body_orientation(kpts_sequence, confidence_threshold)
        
        fall_features = {}
        
        # 1. Rapid downward motion (key fall indicator)
        fall_features['downward_velocity'] = com_vel[:, 1]  # Y-velocity (positive = downward)
        fall_features['downward_acceleration'] = com_acc[:, 1]  # Y-acceleration
        
        # 2. Sudden orientation changes
        fall_features['spine_angle_velocity'] = np.gradient(orientations['spine_angle'])
        fall_features['shoulder_tilt_velocity'] = np.gradient(orientations['shoulder_line_angle'])
        
        # 3. Loss of balance indicators
        fall_features['com_displacement'] = np.linalg.norm(com_vel, axis=1)  # Overall COM movement
        fall_features['vertical_instability'] = np.abs(orientations['spine_angle'])  # Deviation from upright
        
        # 4. Body compactness changes (people often curl up when falling)
        fall_features['compactness_change'] = np.gradient(orientations['body_compactness'])
        
        # 5. Limb motion patterns
        # High arm movement often indicates loss of balance
        arm_indices = [2, 3, 4, 5, 6, 7]  # Shoulders, elbows, wrists
        if T > 1:
            fall_features['arm_motion_intensity'] = np.mean(vel_mags[:, arm_indices], axis=1)
        else:
            fall_features['arm_motion_intensity'] = np.array([0.0])
        
        # 6. Ground proximity (lower body getting closer to ground level)
        lower_body_indices = [8, 9, 10, 11, 12, 13]
        fall_features['lower_body_height'] = np.zeros(T)
        for t in range(T):
            valid_lower = kpts_sequence[t, lower_body_indices, :]
            valid_mask = valid_lower[:, 2] > confidence_threshold
            if np.sum(valid_mask) > 0:
                # Average Y coordinate of valid lower body points (higher Y = lower in image)
                fall_features['lower_body_height'][t] = np.mean(valid_lower[valid_mask, 1])
        
        # 7. Asymmetry features (falls often create body asymmetry)
        fall_features['left_right_asymmetry'] = np.zeros(T-1)
        for t in range(T-1):
            # Compare left vs right side motion
            right_motion = np.mean(vel_mags[t, [2, 3, 4, 8, 9, 10]])  # Right side
            left_motion = np.mean(vel_mags[t, [5, 6, 7, 11, 12, 13]])  # Left side
            if right_motion + left_motion > 0:
                fall_features['left_right_asymmetry'][t] = abs(right_motion - left_motion) / (right_motion + left_motion)
        
        return fall_features
    
    def extract_all_features(self, kpts_sequence, confidence_threshold=0.1, image_size=None):
        """
        Extract streamlined kinematic features for fall detection (optimized for 25 features)
        
        Args:
            kpts_sequence: (T, 18, 3) - keypoint sequence
            image_size: (H, W) tuple or None
        
        Returns:
            features: Dictionary of essential features for 25-dim vector
        """
        # Only extract features that are actually used in create_feature_vector
        com_traj, com_vel, com_acc = self.compute_center_of_mass(
            kpts_sequence, confidence_threshold, image_size=image_size)
        orientations = self.compute_body_orientation(kpts_sequence, confidence_threshold)
        fall_features = self.compute_fall_specific_features(kpts_sequence, confidence_threshold)
        
        # Return only essential features
        features = {
            'com_velocity': com_vel,
            'com_acceleration': com_acc,
            'orientations': orientations,
            'fall_features': fall_features
        }
        
        return features
    
    def create_feature_vector(self, features, window_size=30):
        """
        Create a compact feature vector with only the most useful fall detection features
        
        Args:
            features: Dictionary of extracted features
            window_size: Expected sequence length
        
        Returns:
            feature_vector: Optimized feature representation (25-dim)
        """
        feature_list = []
        
        # Helper function for key statistics (reduced from 5 to 3 stats)
        def add_key_stats(sequence, name_prefix):
            if len(sequence) > 0:
                feature_list.extend([
                    np.mean(sequence),      # Mean
                    np.std(sequence),       # Standard deviation  
                    np.max(sequence),       # Maximum (peak values important for falls)
                ])
            else:
                feature_list.extend([0.0, 0.0, 0.0])
        
        # Helper for 2-stat features
        def add_basic_stats(sequence, name_prefix):
            if len(sequence) > 0:
                feature_list.extend([
                    np.mean(sequence),      # Mean
                    np.max(sequence),       # Maximum
                ])
            else:
                feature_list.extend([0.0, 0.0])
        
        # TIER 1: Critical Fall Indicators (12 features)
        
        # 1. Downward velocity (Y-component) - 3 features
        if len(features['fall_features'].get('downward_velocity', [])) > 0:
            add_key_stats(features['fall_features']['downward_velocity'], 'downward_vel')
        else:
            feature_list.extend([0.0, 0.0, 0.0])
        
        # 2. Downward acceleration (Y-component) - 3 features  
        if len(features['fall_features'].get('downward_acceleration', [])) > 0:
            add_key_stats(features['fall_features']['downward_acceleration'], 'downward_acc')
        else:
            feature_list.extend([0.0, 0.0, 0.0])
        
        # 3. Spine angle velocity (rate of posture change) - 3 features
        if len(features['fall_features'].get('spine_angle_velocity', [])) > 0:
            add_key_stats(features['fall_features']['spine_angle_velocity'], 'spine_vel')
        else:
            feature_list.extend([0.0, 0.0, 0.0])
        
        # 4. Vertical instability (deviation from upright) - 3 features
        if len(features['fall_features'].get('vertical_instability', [])) > 0:
            add_key_stats(features['fall_features']['vertical_instability'], 'vert_instab')
        else:
            feature_list.extend([0.0, 0.0, 0.0])
        
        # TIER 2: Strong Supporting Features (8 features)
        
        # 5. COM displacement (overall movement magnitude) - 2 features
        if len(features['fall_features'].get('com_displacement', [])) > 0:
            add_basic_stats(features['fall_features']['com_displacement'], 'com_disp')
        else:
            feature_list.extend([0.0, 0.0])
        
        # 6. Lower body height (ground proximity) - 2 features
        if len(features['fall_features'].get('lower_body_height', [])) > 0:
            lower_height = features['fall_features']['lower_body_height']
            # Focus on minimum height and rate of change
            feature_list.extend([
                np.min(lower_height),                    # Closest to ground
                np.max(np.diff(lower_height)) if len(lower_height) > 1 else 0.0  # Max rate of descent
            ])
        else:
            feature_list.extend([0.0, 0.0])  # Default: no lower body info
        
        # 7. Arm motion intensity (balance loss indicator) - 2 features
        if len(features['fall_features'].get('arm_motion_intensity', [])) > 0:
            add_basic_stats(features['fall_features']['arm_motion_intensity'], 'arm_motion')
        else:
            feature_list.extend([0.0, 0.0])
        
        # 8. Left-right asymmetry (unbalanced motion) - 2 features
        if len(features['fall_features'].get('left_right_asymmetry', [])) > 0:
            add_basic_stats(features['fall_features']['left_right_asymmetry'], 'asymmetry')
        else:
            feature_list.extend([0.0, 0.0])
        
        # TIER 3: Derived Features (5 features)
        
        # 9. Velocity magnitude (overall speed) - 2 features
        if len(features['com_velocity']) > 0:
            vel_magnitude = np.linalg.norm(features['com_velocity'], axis=1)
            add_basic_stats(vel_magnitude, 'vel_mag')
        else:
            feature_list.extend([0.0, 0.0])
        
        # 10. Acceleration magnitude (overall acceleration) - 2 features
        if len(features['com_acceleration']) > 0:
            acc_magnitude = np.linalg.norm(features['com_acceleration'], axis=1)
            add_basic_stats(acc_magnitude, 'acc_mag')
        else:
            feature_list.extend([0.0, 0.0])
        
        # 11. Postural stability index (combined spine angle + COM movement) - 1 feature
        if (len(features['orientations'].get('spine_angle', [])) > 0 and 
            len(features['fall_features'].get('com_displacement', [])) > 0):
            spine_instability = np.mean(np.abs(features['orientations']['spine_angle']))
            com_movement = np.mean(features['fall_features']['com_displacement'])
            postural_stability = spine_instability * (1 + com_movement / 100.0)  # Combined metric
            feature_list.append(postural_stability)
        else:
            feature_list.append(0.0)
        
        # Total: 12 + 8 + 5 = 25 optimized features
        return np.array(feature_list, dtype=np.float32)

def save_kinematic_features(features, output_path, format='pt'):
    """Save kinematic features to file"""
    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    
    if format == 'pt':
        torch.save(features, output_path)
    elif format == 'npy':
        np.save(output_path, features)
    else:
        raise ValueError(f"Unsupported format: {format}")


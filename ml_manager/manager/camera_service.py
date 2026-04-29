"""
Camera Service — Unified camera feed ingestion using OpenCV.
Supports: USB cameras, RTSP streams, HTTP streams, video files.
"""

import cv2
import time
import threading
from typing import Optional, Callable
import numpy as np


class CameraService:
    """
    Captures frames from any camera source using OpenCV.
    All sources use the same cv2.VideoCapture interface.
    """

    def __init__(self, source: str = "0", fps: int = 30, width: int = 640, height: int = 480):
        """
        Args:
            source: Camera source string.
                - "0", "1", etc. for USB cameras (device index)
                - "rtsp://..." for RTSP IP cameras
                - "http://..." for HTTP IP cameras
                - "/videos/sample.mp4" for video files
            fps: Target frames per second
            width: Frame width
            height: Frame height
        """
        self.source = source
        self.fps = fps
        self.width = width
        self.height = height
        self.cap: Optional[cv2.VideoCapture] = None
        self._running = False
        self._frame_id = 0
        self._lock = threading.Lock()
        self._latest_frame: Optional[np.ndarray] = None

    def _parse_source(self, source: str):
        """Convert source string to cv2.VideoCapture compatible format."""
        # USB camera (numeric device index)
        if source.isdigit():
            return int(source)
        
        # Robust path mapping for Docker environment
        # If user passes F:\... or videos\... map it to /videos
        normalized = source.replace("\\", "/")
        if "videos/" in normalized:
            # Extract everything from videos/ onwards
            suffix = normalized[normalized.find("videos/"):]
            return "/" + suffix
            
        # RTSP, HTTP, or direct file path — pass directly
        return source

    def open(self) -> bool:
        """Open the camera source."""
        parsed = self._parse_source(self.source)
        self.cap = cv2.VideoCapture(parsed)

        if not self.cap.isOpened():
            print(f"❌ Failed to open camera source: {self.source}")
            return False

        # Set resolution if USB camera
        if isinstance(parsed, int):
            self.cap.set(cv2.CAP_PROP_FRAME_WIDTH, self.width)
            self.cap.set(cv2.CAP_PROP_FRAME_HEIGHT, self.height)
            self.cap.set(cv2.CAP_PROP_FPS, self.fps)

        print(f"✅ Camera opened: {self.source}")
        actual_w = int(self.cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        actual_h = int(self.cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        actual_fps = self.cap.get(cv2.CAP_PROP_FPS)
        print(f"   Resolution: {actual_w}x{actual_h}, FPS: {actual_fps}")
        return True

    def read_frame(self) -> tuple[bool, Optional[np.ndarray], int]:
        """
        Read a single frame from the camera.

        Returns:
            (success, frame, frame_id)
        """
        if self.cap is None or not self.cap.isOpened():
            return False, None, -1

        ret, frame = self.cap.read()
        if not ret:
            # For video files, loop back to start
            if not self.source.isdigit() and not self.source.startswith(("rtsp://", "http://")):
                self.cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
                ret, frame = self.cap.read()
                if not ret:
                    return False, None, -1

            else:
                return False, None, -1

        self._frame_id += 1

        # Resize if needed
        if frame.shape[1] != self.width or frame.shape[0] != self.height:
            frame = cv2.resize(frame, (self.width, self.height))

        with self._lock:
            self._latest_frame = frame.copy()

        return True, frame, self._frame_id

    def get_latest_frame(self) -> Optional[np.ndarray]:
        """Get the latest captured frame (thread-safe)."""
        with self._lock:
            return self._latest_frame.copy() if self._latest_frame is not None else None

    def release(self):
        """Release the camera."""
        if self.cap is not None:
            self.cap.release()
            self.cap = None
            print(f"📷 Camera released: {self.source}")

    @property
    def is_opened(self) -> bool:
        return self.cap is not None and self.cap.isOpened()

    def get_frame_delay(self) -> float:
        """Get delay between frames based on target FPS."""
        return 1.0 / self.fps if self.fps > 0 else 0.033

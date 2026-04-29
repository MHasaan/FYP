"""
Base Worker — Abstract base class for all ML model workers.
Each worker wraps a model and provides a standardized interface.
"""

import time
from abc import ABC, abstractmethod
from typing import Any, Optional
import numpy as np


class BaseWorker(ABC):
    """
    Abstract base class for all ML pipeline workers.

    Each worker must implement:
        - load_model(): Load model weights/files
        - process(): Run inference on input data
        - unload_model(): Release model resources

    The worker tracks processing time and provides a common interface
    for the pipeline orchestrator.
    """

    def __init__(self, name: str, model_path: Optional[str] = None):
        self.name = name
        self.model_path = model_path
        self.model = None
        self.is_loaded = False
        self._total_frames = 0
        self._total_time_ms = 0.0

    @abstractmethod
    def load_model(self):
        """Load the ML model. Called once on startup."""
        pass

    @abstractmethod
    def process(self, inputs: dict[str, Any]) -> dict[str, Any]:
        """
        Run inference on the given inputs.

        Args:
            inputs: Dictionary of named inputs. The keys depend on the
                    pipeline DAG dependencies. Common keys:
                    - "frame": raw numpy frame (H, W, C)
                    - "pose": pose estimation keypoints
                    - "preproc_1", "preproc_2", "preproc_3": preprocessing results

        Returns:
            Dictionary of named outputs that downstream steps can consume.
        """
        pass

    @abstractmethod
    def unload_model(self):
        """Release model resources. Called on shutdown."""
        pass

    def run(self, inputs: dict[str, Any]) -> tuple[dict[str, Any], float]:
        """
        Run the worker with timing. Used by the pipeline orchestrator.

        Returns:
            (outputs, processing_time_ms)
        """
        start = time.perf_counter()
        outputs = self.process(inputs)
        elapsed_ms = (time.perf_counter() - start) * 1000

        self._total_frames += 1
        self._total_time_ms += elapsed_ms

        return outputs, elapsed_ms

    @property
    def avg_processing_time_ms(self) -> float:
        if self._total_frames == 0:
            return 0.0
        return self._total_time_ms / self._total_frames

    def update_config(self, config: dict[str, Any]):
        """
        Update worker configuration dynamically.

        Override this method in subclasses to support runtime configuration
        changes (e.g., confidence thresholds, target classes).

        Args:
            config: Dictionary of configuration options
        """
        pass  # Default implementation does nothing

    def get_config(self) -> dict[str, Any]:
        """
        Get current worker configuration.

        Override this method in subclasses to return configurable settings.

        Returns:
            Dictionary of current configuration
        """
        return {}

    def __repr__(self):
        return f"<{self.__class__.__name__} name={self.name} loaded={self.is_loaded}>"

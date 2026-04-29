"""
Test Worker
A simple worker that does nothing to the frame, used just to show the feed.
"""

from typing import Any, Optional
from manager.workers.base_worker import BaseWorker

class TestWorker(BaseWorker):
    def __init__(self):
        super().__init__(name="test")

    def load_model(self):
        self.is_loaded = True

    def process(self, inputs: dict[str, Any]) -> dict[str, Any]:
        # Does nothing, just passes through
        return {"test_active": True}

    def unload_model(self):
        self.is_loaded = False

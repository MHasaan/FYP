"""
ML Manager — Main Entry Point

Orchestrates multiple ML pipelines:
1. Listens for control commands from Backend via Redis
2. Creates/manages pipeline instances for different cameras
3. Each instance captures frames, runs models, publishes results

Supports multi-camera setups with per-camera model configuration.
"""

import os
import signal
import sys

from manager.pipeline_manager import PipelineManager
from manager.gdino_service import GDinoService


def main():
    """Entry point for the ML Manager service."""
    print("=" * 60)
    print("FYP ML Manager Starting (Multi-Pipeline Mode)...")
    print("=" * 60)

    manager = PipelineManager()
    # Visual Search runs as a separate background service so its heavy
    # per-image GroundingDINO inference never blocks the live pipeline.
    gdino = GDinoService()
    gdino.start()

    # Handle graceful shutdown
    def signal_handler(sig, frame):
        print("\nShutdown signal received...")
        gdino.stop()
        manager.shutdown()
        sys.exit(0)

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    # Start listening for commands
    print("Ready to receive pipeline commands")
    manager.listen_for_commands()


if __name__ == "__main__":
    main()

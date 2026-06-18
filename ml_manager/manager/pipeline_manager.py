"""
Multi-Pipeline Manager

Manages multiple concurrent pipeline instances, each with its own:
- Camera source
- Enabled model configuration
- Model-specific settings (confidence thresholds, etc.)
- Redis channels for results/frames

This allows running multiple cameras with different model configurations
simultaneously.
"""

import os
import json
import time
import base64
import threading
from datetime import datetime, timezone
from dataclasses import dataclass, field
from typing import Optional, Any, Callable
from concurrent.futures import ThreadPoolExecutor

import cv2
import numpy as np
import redis
from redis.exceptions import ConnectionError, TimeoutError

from manager.pipeline import Pipeline
from manager.camera_service import CameraService
from manager.workers.base_worker import BaseWorker
from manager.workers.pose_worker import PoseWorker
from manager.workers.test_worker import TestWorker
from manager.workers.patch_extraction_worker import PatchExtractionWorker
from manager.workers.global_patch_worker import GlobalPatchWorker
from manager.workers.kinematics_worker import KinematicsWorker
from manager.workers.fall_detection_worker import FallDetectionWorker
from manager.workers.seizure_detection_worker import SeizureDetectionWorker


@dataclass
class PipelineInstanceConfig:
    """Configuration for a single pipeline instance."""
    instance_id: int
    name: str
    camera_source: str
    camera_config: dict = field(default_factory=dict)
    enabled_models: list[str] = field(default_factory=list)
    model_configs: dict = field(default_factory=dict)
    session_id: Optional[int] = None


class PipelineInstance:
    """
    A single pipeline instance managing one camera feed and its configured models.
    """

    # Available worker factories
    WORKER_FACTORIES: dict[str, Callable[[], BaseWorker]] = {
        "pose": lambda: PoseWorker(),
        "patch_extraction": lambda: PatchExtractionWorker(indices_name="fall"),
        "patch_extraction_seizure": lambda: PatchExtractionWorker(indices_name="seizure"),
        "global_patch": lambda: GlobalPatchWorker(),
        "kinematics": lambda: KinematicsWorker(),
        "fall_detection": lambda: FallDetectionWorker(),
        "seizure_detection": lambda: SeizureDetectionWorker(),
        "test": lambda: TestWorker(),
    }

    # Default DAG dependencies
    DEPENDENCIES = {
        "pose": [],
        "patch_extraction": ["pose"],
        "patch_extraction_seizure": ["pose"],
        "global_patch": ["pose"],
        "kinematics": ["pose"],
        "fall_detection": ["pose", "patch_extraction", "global_patch", "kinematics"],
        "seizure_detection": ["pose", "kinematics", "patch_extraction_seizure"],
        "test": [],
    }

    # Default input keys for each worker
    INPUT_KEYS = {
        "pose": ["frame"],
        "patch_extraction": ["frame", "pose"],
        "patch_extraction_seizure": ["frame", "pose"],
        "global_patch": ["frame", "pose"],
        "kinematics": ["pose"],
        "fall_detection": ["frame", "pose", "patches", "global_patch", "kinematic_features"],
        "seizure_detection": ["frame", "pose", "kinematic_features", "kinematic_ready", "patches_seizure"],
        "test": ["frame"],
    }

    def __init__(self, config: PipelineInstanceConfig, redis_client: redis.Redis):
        self.config = config
        self.redis = redis_client
        self.pipeline = Pipeline()
        self.camera: Optional[CameraService] = None

        # State
        self.is_running = False
        self.is_paused = False
        self.frames_processed = 0
        self.current_fps = 0.0
        self.last_error: Optional[str] = None
        self._stop_event = threading.Event()
        self._processing_thread: Optional[threading.Thread] = None

        # Recording state
        self.recording_id: Optional[int] = None
        self.recording_file_path: Optional[str] = None
        self.recording_writer: Optional[cv2.VideoWriter] = None
        self.recording_started_at: Optional[float] = None
        self.recording_frame_count = 0

        # Redis channels (instance-specific)
        self.results_channel = f"pipeline:{config.instance_id}:results"
        self.frames_channel = f"pipeline:{config.instance_id}:frames"
        self.status_key = f"pipeline:{config.instance_id}:status"

        # Setup pipeline with configured models
        self._setup_pipeline()

    def _setup_pipeline(self):
        """Configure the pipeline with enabled models only.

        Auto-expands transitive dependencies: e.g. enabling 'fall_detection'
        automatically enables 'pose', 'patch_extraction', 'global_patch',
        and 'kinematics', even if the user didn't explicitly select them.
        """
        enabled = list(self.config.enabled_models or list(self.WORKER_FACTORIES.keys()))

        # Auto-expand: recursively add any missing dependencies
        expanded = set(enabled)
        changed = True
        while changed:
            changed = False
            for model_name in list(expanded):
                for dep in self.DEPENDENCIES.get(model_name, []):
                    if dep not in expanded and dep in self.WORKER_FACTORIES:
                        expanded.add(dep)
                        changed = True

        # Topologically sort enabled models so dependencies are added first
        enabled = list(expanded)
        sorted_enabled = []
        remaining = set(enabled)
        while remaining:
            ready = [m for m in remaining
                     if all(d not in remaining or d in sorted_enabled
                            for d in self.DEPENDENCIES.get(m, []))]
            if not ready:
                # Shouldn't happen (DAG verified), but fall back to original order
                sorted_enabled.extend(sorted(remaining))
                break
            sorted_enabled.extend(sorted(ready))  # deterministic order within level
            remaining -= set(ready)
        enabled = sorted_enabled

        print(f"[Instance {self.config.instance_id}] Setting up pipeline with models: {enabled}")

        for model_name in enabled:
            if model_name not in self.WORKER_FACTORIES:
                print(f"[Instance {self.config.instance_id}] Unknown model: {model_name}, skipping")
                continue

            # Create worker
            worker = self.WORKER_FACTORIES[model_name]()

            # Apply model-specific config if provided
            if model_name in self.config.model_configs:
                model_cfg = self.config.model_configs[model_name]
                if hasattr(worker, 'update_config'):
                    worker.update_config(model_cfg)

            # Get dependencies (only include those that are also enabled)
            deps = [d for d in self.DEPENDENCIES.get(model_name, []) if d in enabled]
            input_keys = self.INPUT_KEYS.get(model_name, [])

            self.pipeline.add_step(
                name=model_name,
                worker=worker,
                depends_on=deps,
                input_keys=input_keys,
            )

        print(f"[Instance {self.config.instance_id}] Pipeline execution plan:")
        print(self.pipeline)

    def load_models(self):
        """Load all models for this instance."""
        print(f"[Instance {self.config.instance_id}] Loading models...")
        self.pipeline.load_all_models()

    def unload_models(self):
        """Unload all models for this instance."""
        print(f"[Instance {self.config.instance_id}] Unloading models...")
        self.pipeline.unload_all_models()

    def update_model_config(self, model_name: str, config: dict):
        """Update configuration for a specific model."""
        if model_name in self.pipeline.steps:
            worker = self.pipeline.steps[model_name].worker
            if hasattr(worker, 'update_config'):
                worker.update_config(config)
                self.config.model_configs[model_name] = config
                print(f"[Instance {self.config.instance_id}] Updated config for {model_name}: {config}")

    def start(self):
        """Start processing in a background thread."""
        if self.is_running:
            print(f"[Instance {self.config.instance_id}] Already running")
            return

        self._stop_event.clear()
        self._processing_thread = threading.Thread(
            target=self._processing_loop,
            daemon=False,
        )
        self._processing_thread.start()

    def stop(self):
        """Stop processing."""
        if not self.is_running:
            return

        print(f"[Instance {self.config.instance_id}] Stopping...")
        self._stop_event.set()

        if self._processing_thread:
            self._processing_thread.join(timeout=10)

    def pause(self):
        """Pause processing (keeps camera open)."""
        self.is_paused = True
        self._update_status()

    def resume(self):
        """Resume processing."""
        self.is_paused = False
        self._update_status()

    def start_recording(self, recording_id: int, file_path: str) -> bool:
        """Start writing frames for this instance to a recording file."""
        try:
            folder = os.path.dirname(file_path)
            if folder:
                os.makedirs(folder, exist_ok=True)

            target_fps = float(self.current_fps) if self.current_fps > 1 else float(self.camera.fps if self.camera else 20)
            target_fps = max(1.0, target_fps)
            writer = cv2.VideoWriter(
                file_path,
                cv2.VideoWriter_fourcc(*"mp4v"),
                target_fps,
                (self.camera.width if self.camera else 640, self.camera.height if self.camera else 480),
            )
            if not writer.isOpened():
                print(f"[Instance {self.config.instance_id}] Failed to open recording writer: {file_path}")
                return False

            self.recording_writer = writer
            self.recording_id = recording_id
            self.recording_file_path = file_path
            self.recording_started_at = time.time()
            self.recording_frame_count = 0

            self._publish_recording_status("recording")
            print(f"[Instance {self.config.instance_id}] Recording started: {file_path}")
            return True
        except Exception as e:
            print(f"[Instance {self.config.instance_id}] start_recording error: {e}")
            return False

    def stop_recording(self) -> dict[str, Any]:
        """Stop active recording and return finalized metadata."""
        metadata = {
            "status": "completed",
            "recording_id": self.recording_id,
            "file_path": self.recording_file_path,
            "frame_count": self.recording_frame_count,
            "fps": self.current_fps,
            "width": self.camera.width if self.camera else 0,
            "height": self.camera.height if self.camera else 0,
            "codec": "mp4v",
            "duration_seconds": 0.0,
            "file_size_bytes": 0,
            "ended_at": datetime.now(timezone.utc).isoformat(),
        }

        try:
            if self.recording_writer is not None:
                self.recording_writer.release()
        except Exception as e:
            print(f"[Instance {self.config.instance_id}] stop_recording release error: {e}")

        if self.recording_started_at is not None:
            metadata["duration_seconds"] = max(0.0, time.time() - self.recording_started_at)

        if self.recording_file_path and os.path.exists(self.recording_file_path):
            try:
                metadata["file_size_bytes"] = os.path.getsize(self.recording_file_path)
            except OSError:
                pass

        self._publish_recording_status("completed", metadata)

        self.recording_writer = None
        self.recording_id = None
        self.recording_file_path = None
        self.recording_started_at = None
        self.recording_frame_count = 0

        return metadata

    def _publish_recording_status(self, status: str, extra: Optional[dict[str, Any]] = None):
        if self.recording_id is None:
            return

        payload = {
            "status": status,
            "instance_id": str(self.config.instance_id),
            "recording_id": str(self.recording_id),
            "file_path": self.recording_file_path or "",
            "frame_count": str(self.recording_frame_count),
            "fps": str(round(self.current_fps, 2)),
            "width": str(self.camera.width if self.camera else 0),
            "height": str(self.camera.height if self.camera else 0),
            "codec": "mp4v",
            "updated_at": datetime.now(timezone.utc).isoformat(),
        }
        if extra:
            for key, value in extra.items():
                payload[key] = "" if value is None else str(value)

        key = f"recording:{self.recording_id}:status"
        try:
            self.redis.hset(key, mapping=payload)
            self.redis.expire(key, 3600)
        except Exception as e:
            print(f"[Instance {self.config.instance_id}] Failed to publish recording status: {e}")

    def _processing_loop(self):
        """Main frame processing loop."""
        self.is_running = True
        self.is_paused = False
        self.frames_processed = 0
        self.last_error = None

        # Setup camera
        cam_cfg = self.config.camera_config
        fps = int(cam_cfg.get("fps", 30))
        width = int(cam_cfg.get("width", 640))
        height = int(cam_cfg.get("height", 480))

        self.camera = CameraService(
            source=self.config.camera_source,
            fps=fps,
            width=width,
            height=height,
        )

        if not self.camera.open():
            self.last_error = "Failed to open camera"
            self.is_running = False
            self._update_status()
            return

        self._update_status()
        print(f"[Instance {self.config.instance_id}] Started processing (session={self.config.session_id})")

        # FPS tracking
        fps_counter_start = time.perf_counter()
        fps_frame_count = 0

        while not self._stop_event.is_set():
            if self.is_paused:
                time.sleep(0.1)
                continue

            # Capture frame
            success, frame, frame_id = self.camera.read_frame()
            if not success:
                time.sleep(0.1)
                continue

            # Process through pipeline
            try:
                results, timing = self.pipeline.process_frame(frame, frame_id)
            except Exception as e:
                self.last_error = str(e)
                print(f"[Instance {self.config.instance_id}] Pipeline error on frame {frame_id}: {e}")
                continue

            # Publish results to Redis
            result_payload = {
                "instance_id": self.config.instance_id,
                "frame_id": frame_id,
                "session_id": self.config.session_id,
                "timestamp": time.time(),
                "results": results,
                "timing": timing,
                "total_processing_time_ms": sum(timing.values()),
            }
            self._safe_publish(self.results_channel, json.dumps(result_payload, default=str))

            # Publish annotated frame (JPEG, base64)
            try:
                _, jpeg_buffer = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, 70])
                frame_b64 = base64.b64encode(jpeg_buffer).decode("utf-8")
                frame_payload = json.dumps({
                    "instance_id": self.config.instance_id,
                    "frame_id": frame_id,
                    "image": frame_b64,
                })
                self._safe_publish(self.frames_channel, frame_payload)
            except Exception as e:
                print(f"[Instance {self.config.instance_id}] Frame publish error: {e}")

            # Write frame to active recording if enabled.
            if self.recording_writer is not None:
                try:
                    self.recording_writer.write(frame)
                    self.recording_frame_count += 1
                    if self.recording_frame_count % 30 == 0:
                        self._publish_recording_status("recording")
                except Exception as e:
                    print(f"[Instance {self.config.instance_id}] Recording write error: {e}")

            self.frames_processed += 1
            fps_frame_count += 1

            # Update FPS every second
            elapsed = time.perf_counter() - fps_counter_start
            if elapsed >= 1.0:
                self.current_fps = fps_frame_count / elapsed
                fps_frame_count = 0
                fps_counter_start = time.perf_counter()
                self._update_status()

            # Frame delay
            frame_delay = self.camera.get_frame_delay()
            total_processing = sum(timing.values()) / 1000.0
            sleep_time = max(0, frame_delay - total_processing)
            if sleep_time > 0:
                time.sleep(sleep_time)

        # Cleanup
        if self.recording_writer is not None:
            self.stop_recording()

        if self.camera:
            self.camera.release()
        self.is_running = False
        self._update_status()
        print(f"[Instance {self.config.instance_id}] Stopped (processed {self.frames_processed} frames)")

    def _safe_publish(self, channel: str, message: str, max_retries: int = 3):
        """Publish to Redis with retry."""
        for attempt in range(max_retries):
            try:
                self.redis.publish(channel, message)
                return True
            except (ConnectionError, TimeoutError) as e:
                print(f"[Instance {self.config.instance_id}] Redis publish failed: {e}")
                time.sleep(0.1 * (attempt + 1))
        return False

    def _update_status(self):
        """Update status in Redis."""
        status = {
            "instance_id": str(self.config.instance_id),
            "name": self.config.name,
            "is_running": str(self.is_running).lower(),
            "is_paused": str(self.is_paused).lower(),
            "session_id": str(self.config.session_id or ""),
            "camera_source": self.config.camera_source,
            "enabled_models": json.dumps(self.config.enabled_models),
            "fps": str(round(self.current_fps, 1)),
            "frames_processed": str(self.frames_processed),
            "last_error": self.last_error or "",
        }
        try:
            self.redis.hset(self.status_key, mapping=status)
        except Exception as e:
            print(f"[Instance {self.config.instance_id}] Failed to update status: {e}")

    def get_status(self) -> dict:
        """Get instance status."""
        return {
            "instance_id": self.config.instance_id,
            "name": self.config.name,
            "is_running": self.is_running,
            "is_paused": self.is_paused,
            "session_id": self.config.session_id,
            "camera_source": self.config.camera_source,
            "enabled_models": self.config.enabled_models,
            "fps": self.current_fps,
            "frames_processed": self.frames_processed,
            "last_error": self.last_error,
        }

    def shutdown(self):
        """Shutdown the instance."""
        self.stop()
        self.pipeline.shutdown()
        self.unload_models()


class PipelineManager:
    """
    Manages multiple pipeline instances.

    Each instance runs independently with its own camera and model configuration.
    """

    # Redis connection settings
    MAX_RECONNECT_ATTEMPTS = 10
    RECONNECT_BASE_DELAY = 1

    # Control channel for receiving commands
    CONTROL_CHANNEL = "pipeline:control"
    MANAGER_STATUS_KEY = "pipeline:manager:status"

    def __init__(self):
        self.redis_url = os.environ.get("REDIS_URL", "redis://redis:6379/0")
        self.redis: Optional[redis.Redis] = None
        self.instances: dict[int, PipelineInstance] = {}
        self._shutdown_requested = False
        self._instance_lock = threading.Lock()
        self._next_instance_id = 1

        # Connect to Redis
        self._connect_redis()

    def _connect_redis(self) -> bool:
        """Connect to Redis with retry."""
        for attempt in range(self.MAX_RECONNECT_ATTEMPTS):
            try:
                self.redis = redis.from_url(self.redis_url, decode_responses=True)
                self.redis.ping()
                print(f"Connected to Redis at {self.redis_url}")
                return True
            except (ConnectionError, TimeoutError) as e:
                delay = self.RECONNECT_BASE_DELAY * (2 ** attempt)
                print(f"Redis connection failed (attempt {attempt + 1}): {e}")
                if attempt < self.MAX_RECONNECT_ATTEMPTS - 1:
                    time.sleep(delay)
        return False

    def _ensure_redis_connection(self) -> bool:
        """Ensure Redis connection is alive."""
        try:
            if self.redis:
                self.redis.ping()
                return True
        except (ConnectionError, TimeoutError):
            print("Redis connection lost, reconnecting...")
        return self._connect_redis()

    def create_instance(
        self,
        name: str,
        camera_source: str,
        enabled_models: list[str] = None,
        model_configs: dict = None,
        camera_config: dict = None,
        session_id: int = None,
        instance_id: int = None,
    ) -> int:
        """
        Create a new pipeline instance.

        Args:
            instance_id: Optional external ID (e.g., from database).
                         If not provided, generates an internal ID.

        Returns the instance_id.
        """
        with self._instance_lock:
            if instance_id is None:
                instance_id = self._next_instance_id
                self._next_instance_id += 1
            else:
                # Ensure internal counter stays ahead of external IDs
                self._next_instance_id = max(self._next_instance_id, instance_id + 1)

        config = PipelineInstanceConfig(
            instance_id=instance_id,
            name=name,
            camera_source=camera_source,
            camera_config=camera_config or {},
            enabled_models=enabled_models or [],
            model_configs=model_configs or {},
            session_id=session_id,
        )

        instance = PipelineInstance(config, self.redis)
        instance.load_models()

        with self._instance_lock:
            self.instances[instance_id] = instance

        print(f"Created pipeline instance {instance_id}: {name}")
        self._update_manager_status()
        return instance_id

    def get_instance(self, instance_id: int) -> Optional[PipelineInstance]:
        """Get an instance by ID."""
        return self.instances.get(instance_id)

    def start_instance(self, instance_id: int) -> bool:
        """Start a specific instance."""
        instance = self.instances.get(instance_id)
        if instance:
            instance.start()
            return True
        return False

    def stop_instance(self, instance_id: int) -> bool:
        """Stop a specific instance."""
        instance = self.instances.get(instance_id)
        if instance:
            instance.stop()
            return True
        return False

    def pause_instance(self, instance_id: int) -> bool:
        """Pause an instance."""
        instance = self.instances.get(instance_id)
        if instance:
            instance.pause()
            return True
        return False

    def resume_instance(self, instance_id: int) -> bool:
        """Resume an instance."""
        instance = self.instances.get(instance_id)
        if instance:
            instance.resume()
            return True
        return False

    def delete_instance(self, instance_id: int) -> bool:
        """Delete an instance."""
        instance = self.instances.get(instance_id)
        if instance:
            instance.shutdown()
            with self._instance_lock:
                del self.instances[instance_id]
            print(f"Deleted pipeline instance {instance_id}")
            self._update_manager_status()
            return True
        return False

    def update_instance_models(self, instance_id: int, enabled_models: list[str]) -> bool:
        """Update enabled models for an instance (requires restart)."""
        instance = self.instances.get(instance_id)
        if instance:
            was_running = instance.is_running
            if was_running:
                instance.stop()

            # Recreate instance with new models
            instance.config.enabled_models = enabled_models
            instance.pipeline = Pipeline()
            instance._setup_pipeline()
            instance.load_models()

            if was_running:
                instance.start()
            return True
        return False

    def update_instance_config(self, instance_id: int, model_configs: dict) -> bool:
        """Update model configurations (can be done while running)."""
        instance = self.instances.get(instance_id)
        if instance:
            for model_name, config in model_configs.items():
                instance.update_model_config(model_name, config)
            return True
        return False

    def start_instance_recording(self, instance_id: int, recording_id: int, file_path: str) -> bool:
        """Start recording for a specific instance."""
        instance = self.instances.get(instance_id)
        if instance:
            if not instance.is_running:
                print(f"[Instance {instance_id}] Cannot start recording while instance is not running")
                return False
            return instance.start_recording(recording_id, file_path)
        return False

    def stop_instance_recording(self, instance_id: int) -> bool:
        """Stop recording for a specific instance."""
        instance = self.instances.get(instance_id)
        if instance:
            if instance.recording_writer is not None:
                instance.stop_recording()
            return True
        return False

    def get_all_statuses(self) -> list[dict]:
        """Get status of all instances."""
        return [instance.get_status() for instance in self.instances.values()]

    def _update_manager_status(self):
        """Update manager status in Redis."""
        status = {
            "instance_count": str(len(self.instances)),
            "instance_ids": json.dumps(list(self.instances.keys())),
            "running_count": str(sum(1 for i in self.instances.values() if i.is_running)),
        }
        try:
            if self._ensure_redis_connection():
                self.redis.hset(self.MANAGER_STATUS_KEY, mapping=status)
        except Exception as e:
            print(f"Failed to update manager status: {e}")

    def listen_for_commands(self):
        """Listen for control commands from Backend via Redis pub/sub."""
        while not self._shutdown_requested:
            try:
                if not self._ensure_redis_connection():
                    time.sleep(5)
                    continue

                pubsub = self.redis.pubsub()
                pubsub.subscribe(self.CONTROL_CHANNEL)
                print(f"Listening for commands on '{self.CONTROL_CHANNEL}'...")

                for message in pubsub.listen():
                    if self._shutdown_requested:
                        break

                    if message["type"] != "message":
                        continue

                    try:
                        command = json.loads(message["data"])
                        self._handle_command(command)
                    except Exception as e:
                        print(f"Error handling command: {e}")

            except (ConnectionError, TimeoutError) as e:
                print(f"Redis error in listener: {e}")
                if not self._shutdown_requested:
                    time.sleep(3)
            finally:
                try:
                    pubsub.close()
                except:
                    pass

    def _handle_command(self, command: dict):
        """Handle a control command."""
        action = command.get("action")
        instance_id = command.get("instance_id")

        print(f"Received command: {action} (instance_id={instance_id})")

        if action == "create_instance":
            instance_id = command.get("instance_id")
            # Check if instance already exists (idempotent)
            if instance_id and instance_id in self.instances:
                print(f"Instance {instance_id} already exists, updating configuration...")
                instance = self.instances[instance_id]
                if "session_id" in command:
                    instance.config.session_id = command["session_id"]
                if "model_configs" in command:
                    for m_name, m_cfg in command["model_configs"].items():
                        instance.update_model_config(m_name, m_cfg)
            else:
                self.create_instance(
                    name=command.get("name", "Instance"),
                    camera_source=command["camera_source"],
                    enabled_models=command.get("enabled_models"),
                    model_configs=command.get("model_configs"),
                    camera_config=command.get("camera_config"),
                    session_id=command.get("session_id"),
                    instance_id=instance_id,
                )
        elif action == "start" and instance_id:
            self.start_instance(instance_id)
        elif action == "stop" and instance_id:
            self.stop_instance(instance_id)
        elif action == "pause" and instance_id:
            self.pause_instance(instance_id)
        elif action == "resume" and instance_id:
            self.resume_instance(instance_id)
        elif action == "delete" and instance_id:
            self.delete_instance(instance_id)
        elif action == "update_models" and instance_id:
            self.update_instance_models(instance_id, command.get("enabled_models", []))
        elif action == "update_config" and instance_id:
            self.update_instance_config(instance_id, command.get("model_configs", {}))
        elif action == "start_recording" and instance_id:
            recording_id = command.get("recording_id")
            file_path = command.get("file_path")
            if recording_id and file_path:
                self.start_instance_recording(instance_id, int(recording_id), file_path)
        elif action == "stop_recording" and instance_id:
            self.stop_instance_recording(instance_id)
        elif action == "start_legacy":
            # Legacy: create and start a single instance (backwards compatibility)
            instance_id = self.create_instance(
                name=command.get("name", "Session"),
                camera_source=command["camera_source"],
                session_id=command.get("session_id"),
                camera_config=command.get("config", {}),
            )
            self.start_instance(instance_id)
        elif action == "stop_all":
            for inst_id in list(self.instances.keys()):
                self.stop_instance(inst_id)
        else:
            print(f"Unknown command: {action}")

    def shutdown(self):
        """Shutdown all instances and the manager."""
        print("Initiating PipelineManager shutdown...")
        self._shutdown_requested = True

        # Stop all instances
        for instance_id in list(self.instances.keys()):
            try:
                instance = self.instances[instance_id]
                instance.shutdown()
            except Exception as e:
                print(f"Error shutting down instance {instance_id}: {e}")

        self.instances.clear()

        # Close Redis
        if self.redis:
            try:
                self.redis.close()
            except:
                pass

        print("PipelineManager shutdown complete")

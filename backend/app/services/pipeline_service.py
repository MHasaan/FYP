"""
Pipeline Service - Communicates with ML Manager via Redis

Uses async context manager pattern to ensure Redis connections are properly closed.
"""

import json
import redis.asyncio as aioredis
from typing import Optional
from app.config import get_settings

settings = get_settings()


class PipelineService:
    """
    Service to communicate with the ML Manager container via Redis.

    Usage:
        async with PipelineService() as service:
            status = await service.get_status()
    """

    PIPELINE_STATUS_KEY = "pipeline:status"
    MANAGER_STATUS_KEY = "pipeline:manager:status"
    INSTANCE_STATUS_GLOB = "pipeline:*:status"
    PIPELINE_CONTROL_CHANNEL = "pipeline:control"
    PIPELINE_RESULTS_CHANNEL = "pipeline:results"

    def __init__(self):
        self._redis: Optional[aioredis.Redis] = None

    async def __aenter__(self):
        """Async context manager entry - establish Redis connection."""
        self._redis = await aioredis.from_url(settings.redis_url, decode_responses=True)
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit - close Redis connection."""
        if self._redis:
            await self._redis.close()
            self._redis = None

    @property
    def redis(self) -> aioredis.Redis:
        """Get Redis connection, raising if not in context manager."""
        if self._redis is None:
            raise RuntimeError("PipelineService must be used as async context manager")
        return self._redis

    @staticmethod
    def _to_int(value: Optional[str], default: int = 0) -> int:
        try:
            if value in (None, ""):
                return default
            return int(value)
        except (TypeError, ValueError):
            return default

    @staticmethod
    def _to_float(value: Optional[str], default: float = 0.0) -> float:
        try:
            if value in (None, ""):
                return default
            return float(value)
        except (TypeError, ValueError):
            return default

    @staticmethod
    def _parse_models(value: Optional[str]) -> list[str]:
        if not value:
            return []
        try:
            parsed = json.loads(value)
            if isinstance(parsed, list):
                return [str(item) for item in parsed]
        except Exception:
            pass
        return []

    async def _read_instance_statuses(self) -> list[tuple[int, dict]]:
        """Read per-instance status hashes (pipeline:<id>:status)."""
        statuses: list[tuple[int, dict]] = []
        try:
            keys = await self.redis.keys(self.INSTANCE_STATUS_GLOB)
            for key in keys:
                parts = key.split(":")
                if len(parts) != 3:
                    continue

                instance_token = parts[1]
                if not instance_token.isdigit():
                    continue

                instance_id = int(instance_token)
                status = await self.redis.hgetall(key)
                if status:
                    statuses.append((instance_id, status))
        except Exception:
            return []

        statuses.sort(key=lambda item: item[0])
        return statuses

    async def _instance_ids_from_manager(self) -> list[int]:
        """Get known instance IDs from manager status, falling back to status keys."""
        instance_ids: list[int] = []
        try:
            manager_status = await self.redis.hgetall(self.MANAGER_STATUS_KEY)
            raw_ids = manager_status.get("instance_ids")
            if raw_ids:
                parsed_ids = json.loads(raw_ids)
                if isinstance(parsed_ids, list):
                    for value in parsed_ids:
                        if isinstance(value, int):
                            instance_ids.append(value)
                        elif isinstance(value, str) and value.isdigit():
                            instance_ids.append(int(value))
        except Exception:
            instance_ids = []

        if instance_ids:
            return sorted(set(instance_ids))

        statuses = await self._read_instance_statuses()
        return [instance_id for instance_id, _ in statuses]

    async def _broadcast_instance_action(self, action: str) -> dict:
        instance_ids = await self._instance_ids_from_manager()
        if not instance_ids:
            return {"message": f"No instances available to {action}"}

        for instance_id in instance_ids:
            command = {
                "action": action,
                "instance_id": instance_id,
            }
            await self.redis.publish(self.PIPELINE_CONTROL_CHANNEL, json.dumps(command))

        return {"message": f"{action.capitalize()} command sent to {len(instance_ids)} instance(s)"}

    async def get_status(self) -> dict:
        """Get current pipeline status from Redis."""
        try:
            # Prefer current multi-instance keys.
            manager_status = await self.redis.hgetall(self.MANAGER_STATUS_KEY)
            instance_statuses = await self._read_instance_statuses()

            if manager_status or instance_statuses:
                running_count = self._to_int(manager_status.get("running_count"), default=0)
                running_instances = [
                    status for _, status in instance_statuses if status.get("is_running", "false") == "true"
                ]
                selected_status: Optional[dict] = None
                if running_instances:
                    selected_status = running_instances[0]
                elif instance_statuses:
                    # Prefer the most recent/highest instance id when idle.
                    selected_status = instance_statuses[-1][1]

                if not selected_status:
                    return {
                        "is_running": running_count > 0,
                        "active_session_id": None,
                        "camera_source": None,
                        "models_loaded": [],
                        "fps": 0.0,
                        "frames_processed": 0,
                    }

                models_raw = selected_status.get("enabled_models") or selected_status.get("models_loaded")
                instance_running = selected_status.get("is_running", "false") == "true"
                return {
                    "is_running": (running_count > 0) or instance_running,
                    "active_session_id": self._to_int(selected_status.get("session_id"), default=0) or None,
                    "camera_source": selected_status.get("camera_source"),
                    "models_loaded": self._parse_models(models_raw),
                    "fps": self._to_float(selected_status.get("fps"), default=0.0),
                    "frames_processed": self._to_int(selected_status.get("frames_processed"), default=0),
                }

            # Fallback for old single-pipeline deployments.
            status = await self.redis.hgetall(self.PIPELINE_STATUS_KEY)
            if status:
                models_raw = status.get("models_loaded") or status.get("enabled_models")
                return {
                    "is_running": status.get("is_running", "false") == "true",
                    "active_session_id": self._to_int(status.get("session_id"), default=0) or None,
                    "camera_source": status.get("camera_source"),
                    "models_loaded": self._parse_models(models_raw),
                    "fps": self._to_float(status.get("fps"), default=0.0),
                    "frames_processed": self._to_int(status.get("frames_processed"), default=0),
                }

            return {
                "is_running": False,
                "active_session_id": None,
                "camera_source": None,
                "models_loaded": [],
                "fps": 0.0,
                "frames_processed": 0,
            }
        except Exception as e:
            print(f"Error getting pipeline status: {e}")
            return {
                "is_running": False,
                "active_session_id": None,
                "camera_source": None,
                "models_loaded": [],
                "fps": 0.0,
                "frames_processed": 0,
                "error": str(e),
            }

    async def start(self, session_id: int, camera_source: str, config: dict = None) -> dict:
        """Send start command to ML Manager."""
        try:
            command = {
                # PipelineManager handles legacy global start via start_legacy.
                "action": "start_legacy",
                "session_id": session_id,
                "camera_source": camera_source,
                "config": config or {},
                "name": f"Session {camera_source}",
            }
            await self.redis.publish(self.PIPELINE_CONTROL_CHANNEL, json.dumps(command))
            return {"message": "Start command sent to ML Manager"}
        except Exception as e:
            return {"message": f"Failed to send start command: {e}", "error": True}

    async def stop(self) -> dict:
        """Send stop command to ML Manager."""
        try:
            command = {"action": "stop_all"}
            await self.redis.publish(self.PIPELINE_CONTROL_CHANNEL, json.dumps(command))
            return {"message": "Stop command sent to ML Manager"}
        except Exception as e:
            return {"message": f"Failed to send stop command: {e}", "error": True}

    async def pause(self) -> dict:
        """Send pause command to ML Manager."""
        try:
            return await self._broadcast_instance_action("pause")
        except Exception as e:
            return {"message": f"Failed to send pause command: {e}", "error": True}

    async def resume(self) -> dict:
        """Send resume command to ML Manager."""
        try:
            return await self._broadcast_instance_action("resume")
        except Exception as e:
            return {"message": f"Failed to send resume command: {e}", "error": True}

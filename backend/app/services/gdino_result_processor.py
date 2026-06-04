"""
GroundingDinoResultProcessor

Listens on the Redis channel 'grounding_dino:results' for job completions
(or failures) published by the ML manager's GDinoService, and updates the
corresponding GroundingDinoJob row in the database.

This runs alongside ResultProcessor in the FastAPI lifespan. Kept separate
on purpose — Visual Search has nothing to do with the live pipeline's
incident/alert flow, and mixing them would couple two unrelated features.
"""

import asyncio
import json
from datetime import datetime, timezone
from typing import Optional

import redis.asyncio as aioredis
from sqlalchemy import select

from app.config import get_settings
from app.database import async_session
from app.models import GroundingDinoJob

settings = get_settings()

RESULTS_CHANNEL = "grounding_dino:results"


class GroundingDinoResultProcessor:
    def __init__(self):
        self._running = False
        self._task: Optional[asyncio.Task] = None
        self._redis: Optional[aioredis.Redis] = None

    async def start(self):
        if self._running:
            return
        self._running = True
        self._redis = await aioredis.from_url(settings.redis_url, decode_responses=True)
        self._task = asyncio.create_task(self._run_loop())
        print("🚀 GroundingDinoResultProcessor started")

    async def stop(self):
        self._running = False
        if self._task:
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass
        if self._redis:
            await self._redis.close()
            self._redis = None
        print("🛑 GroundingDinoResultProcessor stopped")

    async def _run_loop(self):
        pubsub = self._redis.pubsub()
        await pubsub.subscribe(RESULTS_CHANNEL)
        print(f"📡 Listening for GDino results on '{RESULTS_CHANNEL}'...")

        while self._running:
            try:
                message = await pubsub.get_message(ignore_subscribe_messages=True, timeout=1.0)
                if message and message["type"] == "message":
                    await self._handle_message(message["data"])
            except Exception as exc:
                print(f"❌ GDinoResultProcessor loop error: {exc}")
                await asyncio.sleep(1)

        await pubsub.unsubscribe(RESULTS_CHANNEL)

    async def _handle_message(self, data_str: str):
        try:
            data = json.loads(data_str)
        except Exception as exc:
            print(f"⚠️ GDino result: malformed JSON: {exc}")
            return

        job_id = data.get("job_id")
        if job_id is None:
            return

        status = data.get("status", "completed")
        detections = data.get("detections", []) or []
        summary = data.get("summary", {}) or {}
        output_image_path = data.get("output_image_path")
        output_video_path = data.get("output_video_path")
        error = data.get("error")
        processing_ms = data.get("processing_ms")

        async with async_session() as db:
            result = await db.execute(
                select(GroundingDinoJob).where(GroundingDinoJob.id == job_id)
            )
            job = result.scalar_one_or_none()
            if job is None:
                print(f"⚠️ GDino result for unknown job {job_id} — dropping")
                return

            # Allow intermediate "running" status updates to flow through too.
            if status == "running":
                job.status = "running"
                if job.started_at is None:
                    job.started_at = datetime.now(timezone.utc)
                await db.commit()
                return

            job.status = status
            if output_image_path:
                job.output_image_path = output_image_path
            if output_video_path:
                job.output_video_path = output_video_path
            if detections:
                job.detections = detections
            if summary:
                job.summary = summary
            if error:
                job.error = error
            if processing_ms is not None:
                try:
                    job.processing_ms = float(processing_ms)
                except (TypeError, ValueError):
                    pass
            job.completed_at = datetime.now(timezone.utc)
            if job.started_at is None:
                job.started_at = job.completed_at

            await db.commit()
            print(f"✅ GDino job {job_id} finalized: status={status}, detections={len(detections)}")

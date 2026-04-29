"""
Background scheduled job runner.
"""

import asyncio
from datetime import datetime, timezone, timedelta
from typing import Optional

from croniter import croniter
from sqlalchemy import select

from app.database import async_session
from app.models import ScheduledJob, CameraConfig, Session
from app.services.pipeline_service import PipelineService


class ScheduleRunnerService:
    """Runs scheduled jobs in a background loop."""

    def __init__(self, poll_seconds: int = 10):
        self._poll_seconds = poll_seconds
        self._running = False
        self._task: Optional[asyncio.Task] = None

    async def start(self):
        if self._running:
            return
        self._running = True
        self._task = asyncio.create_task(self._run_loop())

    async def stop(self):
        self._running = False
        if self._task:
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass
            self._task = None

    async def _run_loop(self):
        while self._running:
            try:
                await self._tick()
            except Exception as exc:  # defensive guard for long-running task
                print(f"[ScheduleRunner] tick error: {exc}")
            await asyncio.sleep(self._poll_seconds)

    async def _tick(self):
        now = datetime.now(timezone.utc)
        async with async_session() as db:
            result = await db.execute(
                select(ScheduledJob).where(ScheduledJob.is_active == True)  # noqa: E712
            )
            jobs = result.scalars().all()

            for job in jobs:
                if job.next_run_at is None:
                    # Run once immediately after creation/activation, then compute future schedule.
                    job.next_run_at = now

                if job.next_run_at and job.next_run_at <= now:
                    await self._run_job(db, job)
                    job.last_run_at = now
                    try:
                        next_time = croniter(job.cron_expression, now).get_next(datetime)
                        if next_time.tzinfo is None:
                            next_time = next_time.replace(tzinfo=timezone.utc)
                        job.next_run_at = next_time
                    except Exception:
                        job.last_run_status = "invalid_cron"
                        job.is_active = False

            await db.commit()

    async def _run_job(self, db, job: ScheduledJob):
        cam_result = await db.execute(select(CameraConfig).where(CameraConfig.id == job.camera_config_id))
        camera = cam_result.scalar_one_or_none()
        if camera is None:
            job.last_run_status = "camera_missing"
            return

        async with PipelineService() as service:
            status = await service.get_status()
            if status.get("is_running"):
                job.last_run_status = "skipped_pipeline_running"
                return

            session = Session(
                name=f"Scheduled: {job.name}",
                camera_source=camera.source_url,
                status="running",
                config={
                    "schedule_job_id": job.id,
                    "enabled_models": job.enabled_models,
                    "model_configs": job.model_configs,
                    "cron_expression": job.cron_expression,
                },
            )
            db.add(session)
            await db.flush()

            start_result = await service.start(
                session_id=session.id,
                camera_source=camera.source_url,
                config={
                    "enabled_models": job.enabled_models,
                    "model_configs": job.model_configs,
                },
            )
            if start_result.get("error"):
                session.status = "failed"
                job.last_run_status = "start_failed"
                return

            job.last_run_status = "started"

            if job.duration_minutes and job.duration_minutes > 0:
                asyncio.create_task(self._auto_stop_after(job.duration_minutes, job.id))

    async def _auto_stop_after(self, duration_minutes: int, job_id: int):
        await asyncio.sleep(duration_minutes * 60)
        async with PipelineService() as service:
            status = await service.get_status()
            if status.get("is_running"):
                await service.stop()

        async with async_session() as db:
            result = await db.execute(select(ScheduledJob).where(ScheduledJob.id == job_id))
            job = result.scalar_one_or_none()
            if job:
                job.last_run_status = "auto_stopped"
                await db.commit()

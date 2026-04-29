"""
Scheduled pipeline job routes.
"""

from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models import ScheduledJob, CameraConfig
from app.schemas import ScheduledJobCreate, ScheduledJobUpdate, ScheduledJobResponse


router = APIRouter(prefix="/api/schedules", tags=["Scheduled Jobs"])


@router.get("/", response_model=list[ScheduledJobResponse])
async def list_scheduled_jobs(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(ScheduledJob).order_by(ScheduledJob.created_at.desc()))
    return result.scalars().all()


@router.post("/", response_model=ScheduledJobResponse, status_code=status.HTTP_201_CREATED)
async def create_scheduled_job(payload: ScheduledJobCreate, db: AsyncSession = Depends(get_db)):
    cam_result = await db.execute(select(CameraConfig.id).where(CameraConfig.id == payload.camera_config_id))
    if cam_result.scalar_one_or_none() is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Camera config {payload.camera_config_id} not found",
        )

    db_job = ScheduledJob(
        name=payload.name,
        description=payload.description,
        camera_config_id=payload.camera_config_id,
        enabled_models=payload.enabled_models,
        model_configs=payload.model_configs,
        cron_expression=payload.cron_expression,
        duration_minutes=payload.duration_minutes,
        is_active=True,
    )
    db.add(db_job)
    await db.commit()
    await db.refresh(db_job)
    return db_job


@router.patch("/{job_id}", response_model=ScheduledJobResponse)
async def update_scheduled_job(
    job_id: int,
    payload: ScheduledJobUpdate,
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(ScheduledJob).where(ScheduledJob.id == job_id))
    job = result.scalar_one_or_none()
    if not job:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Scheduled job not found")

    updates = payload.model_dump(exclude_unset=True)
    if "camera_config_id" in updates and updates["camera_config_id"] is not None:
        cam_result = await db.execute(select(CameraConfig.id).where(CameraConfig.id == updates["camera_config_id"]))
        if cam_result.scalar_one_or_none() is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Camera config {updates['camera_config_id']} not found",
            )

    for key, value in updates.items():
        setattr(job, key, value)

    await db.commit()
    await db.refresh(job)
    return job


@router.delete("/{job_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_scheduled_job(job_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(ScheduledJob).where(ScheduledJob.id == job_id))
    job = result.scalar_one_or_none()
    if not job:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Scheduled job not found")

    await db.delete(job)
    await db.commit()


@router.post("/{job_id}/run")
async def run_scheduled_job_now(job_id: int, db: AsyncSession = Depends(get_db)):
    """Manual trigger helper for schedule testing/verification."""
    result = await db.execute(select(ScheduledJob).where(ScheduledJob.id == job_id))
    job = result.scalar_one_or_none()
    if not job:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Scheduled job not found")

    now = datetime.now(timezone.utc)
    job.last_run_at = now
    job.last_run_status = "manual_triggered"
    await db.commit()
    await db.refresh(job)

    return {
        "message": "Scheduled job manually triggered",
        "job_id": job.id,
        "last_run_at": now.isoformat(),
        "last_run_status": job.last_run_status,
    }

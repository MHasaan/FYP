"""
Recording lifecycle routes.
"""

from datetime import datetime, timezone
import json
import asyncio
import csv
import io
from pathlib import Path
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import FileResponse, JSONResponse, StreamingResponse
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.database import get_db
from app.models import Recording, PipelineInstance
from app.schemas import RecordingCreate, RecordingResponse, RecordingStopRequest
from app.services.redis_service import get_redis_client


router = APIRouter(prefix="/api/recordings", tags=["Recordings"])

VIDEOS_ROOT = Path("/videos").resolve()


def _resolve_recording_file(recording: Recording) -> Path:
    target_path = Path(recording.file_path or "")
    if not target_path.is_absolute():
        target_path = VIDEOS_ROOT / target_path
    resolved_path = target_path.resolve()

    if VIDEOS_ROOT not in resolved_path.parents and resolved_path != VIDEOS_ROOT:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid recording path")
    if not resolved_path.exists() or not resolved_path.is_file():
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Recording file not found")
    return resolved_path


@router.get("/", response_model=list[RecordingResponse])
async def list_recordings(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Recording).order_by(Recording.created_at.desc()))
    return result.scalars().all()


@router.get("/{recording_id}", response_model=RecordingResponse)
async def get_recording(recording_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Recording).where(Recording.id == recording_id))
    recording = result.scalar_one_or_none()
    if not recording:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Recording not found")
    return recording


@router.get("/{recording_id}/stream")
async def stream_recording(recording_id: int, db: AsyncSession = Depends(get_db)):
    """Stream a completed recording file for in-app playback."""
    result = await db.execute(select(Recording).where(Recording.id == recording_id))
    recording = result.scalar_one_or_none()
    if not recording:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Recording not found")

    resolved_path = _resolve_recording_file(recording)

    return FileResponse(
        path=str(resolved_path),
        media_type="video/mp4",
        filename=resolved_path.name,
    )


@router.get("/{recording_id}/download")
async def download_recording(recording_id: int, db: AsyncSession = Depends(get_db)):
    """Download a recording file as an attachment."""
    result = await db.execute(select(Recording).where(Recording.id == recording_id))
    recording = result.scalar_one_or_none()
    if not recording:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Recording not found")

    resolved_path = _resolve_recording_file(recording)
    return FileResponse(
        path=str(resolved_path),
        media_type="video/mp4",
        filename=resolved_path.name,
    )


@router.get("/{recording_id}/export/json")
async def export_recording_json(recording_id: int, db: AsyncSession = Depends(get_db)):
    """Export recording metadata as JSON."""
    result = await db.execute(select(Recording).where(Recording.id == recording_id))
    recording = result.scalar_one_or_none()
    if not recording:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Recording not found")

    payload = {
        "id": recording.id,
        "session_id": recording.session_id,
        "pipeline_instance_id": recording.pipeline_instance_id,
        "name": recording.name,
        "file_path": recording.file_path,
        "results_file_path": recording.results_file_path,
        "file_size_bytes": recording.file_size_bytes,
        "duration_seconds": recording.duration_seconds,
        "fps": recording.fps,
        "width": recording.width,
        "height": recording.height,
        "codec": recording.codec,
        "frame_count": recording.frame_count,
        "status": recording.status,
        "started_at": recording.started_at.isoformat() if recording.started_at else None,
        "ended_at": recording.ended_at.isoformat() if recording.ended_at else None,
        "created_at": recording.created_at.isoformat() if recording.created_at else None,
    }
    return JSONResponse(content=payload)


@router.get("/{recording_id}/export/csv")
async def export_recording_csv(recording_id: int, db: AsyncSession = Depends(get_db)):
    """Export recording metadata as single-row CSV."""
    result = await db.execute(select(Recording).where(Recording.id == recording_id))
    recording = result.scalar_one_or_none()
    if not recording:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Recording not found")

    columns = [
        "id",
        "session_id",
        "pipeline_instance_id",
        "name",
        "file_path",
        "results_file_path",
        "file_size_bytes",
        "duration_seconds",
        "fps",
        "width",
        "height",
        "codec",
        "frame_count",
        "status",
        "started_at",
        "ended_at",
        "created_at",
    ]

    data_row = [
        recording.id,
        recording.session_id,
        recording.pipeline_instance_id,
        recording.name,
        recording.file_path,
        recording.results_file_path,
        recording.file_size_bytes,
        recording.duration_seconds,
        recording.fps,
        recording.width,
        recording.height,
        recording.codec,
        recording.frame_count,
        recording.status,
        recording.started_at.isoformat() if recording.started_at else "",
        recording.ended_at.isoformat() if recording.ended_at else "",
        recording.created_at.isoformat() if recording.created_at else "",
    ]

    buffer = io.StringIO()
    writer = csv.writer(buffer)
    writer.writerow(columns)
    writer.writerow(data_row)
    csv_data = buffer.getvalue()
    buffer.close()

    return StreamingResponse(
        iter([csv_data]),
        media_type="text/csv",
        headers={
            "Content-Disposition": f"attachment; filename=recording_{recording.id}.csv",
        },
    )


@router.post("/", response_model=RecordingResponse, status_code=status.HTTP_201_CREATED)
async def start_recording(
    payload: RecordingCreate,
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(PipelineInstance).where(PipelineInstance.id == payload.pipeline_instance_id)
    )
    instance = result.scalar_one_or_none()
    if not instance:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Pipeline instance {payload.pipeline_instance_id} not found",
        )
    if (instance.status or "").lower() != "running":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Pipeline instance {payload.pipeline_instance_id} is not running",
        )

    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    safe_name = (payload.name or f"instance_{payload.pipeline_instance_id}_{timestamp}").replace(" ", "_")
    file_path = f"/videos/recordings/{safe_name}.mp4"

    db_recording = Recording(
        session_id=payload.session_id,
        pipeline_instance_id=payload.pipeline_instance_id,
        name=payload.name,
        file_path=file_path,
        status="recording",
    )
    db.add(db_recording)
    await db.commit()
    await db.refresh(db_recording)

    redis = await get_redis_client()
    await redis.publish(
        "pipeline:control",
        json.dumps({
            "action": "start_recording",
            "instance_id": payload.pipeline_instance_id,
            "recording_id": db_recording.id,
            "file_path": file_path,
        }),
    )

    return db_recording


@router.post("/{recording_id}/stop", response_model=RecordingResponse)
async def stop_recording(
    recording_id: int,
    payload: RecordingStopRequest,
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Recording).where(Recording.id == recording_id))
    recording = result.scalar_one_or_none()
    if not recording:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Recording not found")

    recording.status = payload.status
    recording.ended_at = datetime.now(timezone.utc)

    if payload.results_file_path is not None:
        recording.results_file_path = payload.results_file_path
    if payload.file_size_bytes is not None:
        recording.file_size_bytes = payload.file_size_bytes
    if payload.duration_seconds is not None:
        recording.duration_seconds = payload.duration_seconds
    elif recording.started_at is not None and recording.ended_at is not None:
        recording.duration_seconds = (recording.ended_at - recording.started_at).total_seconds()
    if payload.fps is not None:
        recording.fps = payload.fps
    if payload.width is not None:
        recording.width = payload.width
    if payload.height is not None:
        recording.height = payload.height
    if payload.codec is not None:
        recording.codec = payload.codec
    if payload.frame_count is not None:
        recording.frame_count = payload.frame_count

    await db.commit()
    await db.refresh(recording)

    redis = await get_redis_client()
    await redis.publish(
        "pipeline:control",
        json.dumps({
            "action": "stop_recording",
            "instance_id": recording.pipeline_instance_id,
            "recording_id": recording.id,
        }),
    )

    # Give ML manager a short window to publish finalized recording metadata.
    status_key = f"recording:{recording.id}:status"
    redis_status = {}
    for _ in range(8):
        redis_status = await redis.hgetall(status_key)
        if redis_status.get("status") == "completed":
            break
        await asyncio.sleep(0.25)

    if recording.results_file_path is None and payload.results_file_path is None:
        if redis_status.get("results_file_path"):
            recording.results_file_path = redis_status.get("results_file_path")
    if payload.file_size_bytes is None and redis_status.get("file_size_bytes"):
        recording.file_size_bytes = int(float(redis_status.get("file_size_bytes", "0") or 0))
    if payload.duration_seconds is None and redis_status.get("duration_seconds"):
        recording.duration_seconds = float(redis_status.get("duration_seconds", "0") or 0)
    if payload.fps is None and redis_status.get("fps"):
        recording.fps = float(redis_status.get("fps", "0") or 0)
    if payload.width is None and redis_status.get("width"):
        recording.width = int(float(redis_status.get("width", "0") or 0))
    if payload.height is None and redis_status.get("height"):
        recording.height = int(float(redis_status.get("height", "0") or 0))
    if payload.codec is None and redis_status.get("codec"):
        recording.codec = redis_status.get("codec")
    if payload.frame_count is None and redis_status.get("frame_count"):
        recording.frame_count = int(float(redis_status.get("frame_count", "0") or 0))

    await db.commit()
    await db.refresh(recording)

    return recording


@router.delete("/{recording_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_recording(recording_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Recording).where(Recording.id == recording_id))
    recording = result.scalar_one_or_none()
    if not recording:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Recording not found")

    await db.delete(recording)
    await db.commit()

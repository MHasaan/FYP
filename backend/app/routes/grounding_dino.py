"""
Grounding DINO (Visual Search) routes.

Lets a user submit an image or short video plus a natural-language text
prompt (e.g. "person . wheelchair . walker .") and get back open-set
object detections from the GroundingDINO model running in the ML manager.

This is a *separate entity* from the live pipeline — it does not interact
with PipelineInstance / Session / fall_detection. Each request creates a
GroundingDinoJob row, the request is published to Redis on
'grounding_dino:requests', the ML manager processes it asynchronously,
and result_processor.py updates the row when the result arrives on
'grounding_dino:results'.
"""

from datetime import datetime, timezone
from pathlib import Path
import json
import shutil
import uuid

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from fastapi.responses import FileResponse
from sqlalchemy import select, delete, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models import GroundingDinoJob, UserAccount
from app.schemas import GroundingDinoJobResponse, GroundingDinoJobListResponse
from app.services.auth_service import get_current_user
from app.services.redis_service import get_redis_client


router = APIRouter(prefix="/api/grounding-dino", tags=["Grounding DINO"])

# Storage paths inside the container. Mounted from ./videos on the host
# (see docker-compose.yml). gdino_inputs and gdino_outputs live alongside
# the existing uploads/ folder.
INPUT_DIR = Path("/videos/gdino_inputs")
OUTPUT_DIR = Path("/videos/gdino_outputs")

IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".bmp"}
VIDEO_EXTS = {".mp4", ".mov", ".avi", ".mkv", ".webm"}

MAX_IMAGE_BYTES = 25 * 1024 * 1024   # 25 MB
MAX_VIDEO_BYTES = 200 * 1024 * 1024  # 200 MB

REQUESTS_CHANNEL = "grounding_dino:requests"


async def _store_upload(file: UploadFile, allowed: set[str], max_bytes: int) -> tuple[Path, str, str]:
    """Stream an upload to disk under INPUT_DIR. Returns (path, ext, original_name)."""
    original_name = file.filename or "upload"
    ext = Path(original_name).suffix.lower()
    if ext not in allowed:
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported file type '{ext}'. Allowed: {sorted(allowed)}",
        )

    INPUT_DIR.mkdir(parents=True, exist_ok=True)
    dest = INPUT_DIR / f"{uuid.uuid4().hex}{ext}"

    total = 0
    try:
        with dest.open("wb") as out:
            while True:
                chunk = await file.read(1024 * 1024)
                if not chunk:
                    break
                total += len(chunk)
                if total > max_bytes:
                    out.close()
                    dest.unlink(missing_ok=True)
                    raise HTTPException(
                        status_code=413,
                        detail=f"File exceeds {max_bytes // (1024*1024)} MB limit",
                    )
                out.write(chunk)
    except HTTPException:
        raise
    except Exception as exc:
        dest.unlink(missing_ok=True)
        raise HTTPException(status_code=500, detail=f"Upload failed: {exc}") from exc
    finally:
        await file.close()

    return dest, ext, original_name


def _validate_thresholds(box_threshold: float, text_threshold: float) -> tuple[float, float]:
    if not (0.0 <= box_threshold <= 1.0):
        raise HTTPException(status_code=400, detail="box_threshold must be between 0 and 1")
    if not (0.0 <= text_threshold <= 1.0):
        raise HTTPException(status_code=400, detail="text_threshold must be between 0 and 1")
    return box_threshold, text_threshold


def _normalize_prompt(prompt: str) -> str:
    text = (prompt or "").strip()
    if not text:
        raise HTTPException(status_code=400, detail="prompt is required")
    if len(text) > 500:
        raise HTTPException(status_code=400, detail="prompt is too long (max 500 chars)")
    return text


async def _publish_job(job: GroundingDinoJob):
    """Send the job to the ML manager via Redis."""
    redis = await get_redis_client()
    payload = {
        "job_id": job.id,
        "input_type": job.input_type,
        "input_path": job.input_path,
        "prompt": job.prompt,
        "box_threshold": job.box_threshold,
        "text_threshold": job.text_threshold,
        "output_dir": str(OUTPUT_DIR),
    }
    await redis.publish(REQUESTS_CHANNEL, json.dumps(payload))


@router.post("/detect/image", response_model=GroundingDinoJobResponse, status_code=status.HTTP_202_ACCEPTED, include_in_schema=False)
@router.post("/detect/image/", response_model=GroundingDinoJobResponse, status_code=status.HTTP_202_ACCEPTED)
async def detect_image(
    file: UploadFile = File(...),
    prompt: str = Form(...),
    name: str | None = Form(None),
    box_threshold: float = Form(0.35),
    text_threshold: float = Form(0.25),
    user: UserAccount = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Upload an image + prompt. Returns the job immediately (status='queued')."""
    box_threshold, text_threshold = _validate_thresholds(box_threshold, text_threshold)
    prompt = _normalize_prompt(prompt)

    dest, _, original_name = await _store_upload(file, IMAGE_EXTS, MAX_IMAGE_BYTES)

    job = GroundingDinoJob(
        user_id=user.id,
        name=(name or "").strip() or None,
        input_type="image",
        input_path=str(dest),
        input_original_filename=original_name,
        prompt=prompt,
        box_threshold=box_threshold,
        text_threshold=text_threshold,
        status="queued",
    )
    db.add(job)
    await db.commit()
    await db.refresh(job)

    await _publish_job(job)
    return job


@router.post("/detect/video", response_model=GroundingDinoJobResponse, status_code=status.HTTP_202_ACCEPTED, include_in_schema=False)
@router.post("/detect/video/", response_model=GroundingDinoJobResponse, status_code=status.HTTP_202_ACCEPTED)
async def detect_video(
    file: UploadFile = File(...),
    prompt: str = Form(...),
    name: str | None = Form(None),
    box_threshold: float = Form(0.35),
    text_threshold: float = Form(0.25),
    user: UserAccount = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Upload a video + prompt. Async — poll GET /jobs/{id}."""
    box_threshold, text_threshold = _validate_thresholds(box_threshold, text_threshold)
    prompt = _normalize_prompt(prompt)

    dest, _, original_name = await _store_upload(file, VIDEO_EXTS, MAX_VIDEO_BYTES)

    job = GroundingDinoJob(
        user_id=user.id,
        name=(name or "").strip() or None,
        input_type="video",
        input_path=str(dest),
        input_original_filename=original_name,
        prompt=prompt,
        box_threshold=box_threshold,
        text_threshold=text_threshold,
        status="queued",
    )
    db.add(job)
    await db.commit()
    await db.refresh(job)

    await _publish_job(job)
    return job


@router.get("/jobs", response_model=GroundingDinoJobListResponse, include_in_schema=False)
@router.get("/jobs/", response_model=GroundingDinoJobListResponse)
async def list_jobs(
    limit: int = 50,
    offset: int = 0,
    status_filter: str | None = None,
    user: UserAccount = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """List jobs created by the current user."""
    safe_limit = max(1, min(limit, 200))
    safe_offset = max(0, offset)

    query = select(GroundingDinoJob).where(GroundingDinoJob.user_id == user.id)
    count_query = (
        select(func.count())
        .select_from(GroundingDinoJob)
        .where(GroundingDinoJob.user_id == user.id)
    )

    if status_filter:
        query = query.where(GroundingDinoJob.status == status_filter)
        count_query = count_query.where(GroundingDinoJob.status == status_filter)

    total_result = await db.execute(count_query)
    total = total_result.scalar_one() or 0

    page_result = await db.execute(
        query.order_by(GroundingDinoJob.created_at.desc())
        .offset(safe_offset)
        .limit(safe_limit)
    )
    items = page_result.scalars().all()

    return {"items": items, "total": total, "limit": safe_limit, "offset": safe_offset}


@router.get("/jobs/{job_id}", response_model=GroundingDinoJobResponse)
async def get_job(
    job_id: int,
    user: UserAccount = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Fetch a single job. Used by the frontend to poll status."""
    result = await db.execute(
        select(GroundingDinoJob).where(GroundingDinoJob.id == job_id)
    )
    job = result.scalar_one_or_none()
    if job is None:
        raise HTTPException(status_code=404, detail="Job not found")
    if job.user_id is not None and job.user_id != user.id:
        raise HTTPException(status_code=403, detail="Not your job")
    return job


@router.delete("/jobs/{job_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_job(
    job_id: int,
    user: UserAccount = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Delete a job + its files."""
    result = await db.execute(
        select(GroundingDinoJob).where(GroundingDinoJob.id == job_id)
    )
    job = result.scalar_one_or_none()
    if job is None:
        raise HTTPException(status_code=404, detail="Job not found")
    if job.user_id is not None and job.user_id != user.id:
        raise HTTPException(status_code=403, detail="Not your job")

    # Best-effort cleanup of files. Don't fail the delete if disk cleanup fails.
    for path_str in (job.input_path, job.output_image_path, job.output_video_path):
        if not path_str:
            continue
        try:
            Path(path_str).unlink(missing_ok=True)
        except Exception as exc:
            print(f"⚠️ Failed to delete file {path_str}: {exc}")

    await db.execute(delete(GroundingDinoJob).where(GroundingDinoJob.id == job_id))
    await db.commit()
    return None


@router.get("/jobs/{job_id}/output")
async def get_job_output(
    job_id: int,
    user: UserAccount = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Serve the annotated output (image or video) for a completed job."""
    result = await db.execute(
        select(GroundingDinoJob).where(GroundingDinoJob.id == job_id)
    )
    job = result.scalar_one_or_none()
    if job is None:
        raise HTTPException(status_code=404, detail="Job not found")
    if job.user_id is not None and job.user_id != user.id:
        raise HTTPException(status_code=403, detail="Not your job")

    path = job.output_image_path or job.output_video_path
    if not path or not Path(path).exists():
        raise HTTPException(status_code=404, detail="Output not ready")

    media_type = "image/jpeg"
    if job.output_video_path and path == job.output_video_path:
        media_type = "video/mp4"

    return FileResponse(path, media_type=media_type)

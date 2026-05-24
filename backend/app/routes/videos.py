"""
Video upload routes.

Allows authenticated users to upload a video file via multipart/form-data.
Files are stored at /videos/uploads/<uuid>.<ext> inside the backend container
(which is bind-mounted to ./videos/uploads on the host). The ml_manager
container has the same volume mounted read-write, so it can read the file
when started as a pipeline source.

Endpoint returns the server-side path which can then be used as the
`source_url` of a CameraConfig with source_type='video_file'.
"""

from pathlib import Path
import shutil
import uuid

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile

from app.models import UserAccount
from app.services.auth_service import get_current_user

router = APIRouter(prefix="/api/videos", tags=["Videos"])

# Mount path inside the container — see docker-compose.yml volumes.
UPLOAD_DIR = Path("/videos/uploads")

# Whitelist of accepted file extensions. mp4 is what the pipeline expects;
# others are convenience formats that ffmpeg/OpenCV can still decode.
ALLOWED_EXTS = {".mp4", ".mov", ".avi", ".mkv", ".webm"}

# 500 MB hard cap to prevent fill-the-disk DoS over the public tunnel.
MAX_BYTES = 500 * 1024 * 1024


@router.post("/upload", status_code=201)
async def upload_video(
    file: UploadFile = File(...),
    user: UserAccount = Depends(get_current_user),
):
    """Accept a multipart video upload, store it on the shared volume, and
    return the in-container path the ML manager can read."""

    # Validate extension
    original_name = file.filename or "upload"
    ext = Path(original_name).suffix.lower()
    if ext not in ALLOWED_EXTS:
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported file type '{ext}'. Allowed: {sorted(ALLOWED_EXTS)}",
        )

    UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
    dest_name = f"{uuid.uuid4().hex}{ext}"
    dest_path = UPLOAD_DIR / dest_name

    # Stream the upload to disk so big files don't blow up memory, and enforce
    # the size cap as we go.
    total = 0
    try:
        with dest_path.open("wb") as out:
            while True:
                chunk = await file.read(1024 * 1024)  # 1 MiB chunks
                if not chunk:
                    break
                total += len(chunk)
                if total > MAX_BYTES:
                    out.close()
                    dest_path.unlink(missing_ok=True)
                    raise HTTPException(
                        status_code=413,
                        detail=f"File exceeds {MAX_BYTES // (1024*1024)} MB limit",
                    )
                out.write(chunk)
    except HTTPException:
        raise
    except Exception as exc:
        # Clean up partial file before re-raising
        dest_path.unlink(missing_ok=True)
        raise HTTPException(status_code=500, detail=f"Upload failed: {exc}") from exc
    finally:
        await file.close()

    return {
        "path": str(dest_path),
        "filename": dest_name,
        "original_filename": original_name,
        "size_bytes": total,
        "uploaded_by_user_id": user.id,
    }

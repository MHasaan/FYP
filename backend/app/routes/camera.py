"""
Camera management routes
"""

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import or_, select
from app.database import get_db
from app.models import CameraConfig, PatientProfile, UserAccount
from app.schemas import CameraConfigCreate, CameraConfigResponse, CameraConfigUpdate, CameraSourceRequest
from app.services.auth_service import get_current_user, require_roles

router = APIRouter(prefix="/api/camera", tags=["Camera"])


def _scoped_camera_query(user: UserAccount):
    query = select(CameraConfig)
    if user.role == "admin":
        return query
    if user.role == "caregiver":
        return query.outerjoin(PatientProfile, CameraConfig.patient_id == PatientProfile.id).where(
            or_(CameraConfig.patient_id.is_(None), PatientProfile.caregiver_id == user.id)
        )
    return query.outerjoin(PatientProfile, CameraConfig.patient_id == PatientProfile.id).where(
        or_(
            PatientProfile.relative_user_id == user.id,
            PatientProfile.primary_contact_email == user.email,
        )
    )


async def _validate_patient_scope(patient_id: int | None, user: UserAccount, db: AsyncSession):
    if patient_id is None:
        return

    result = await db.execute(select(PatientProfile).where(PatientProfile.id == patient_id))
    patient = result.scalar_one_or_none()
    if patient is None:
        raise HTTPException(status_code=404, detail="Linked patient not found")

    if user.role == "caregiver" and patient.caregiver_id not in (None, user.id):
        raise HTTPException(status_code=403, detail="Caregiver can only link their assigned patients")


@router.get("/configs", response_model=list[CameraConfigResponse])
async def list_camera_configs(
    user: UserAccount = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """List all saved camera configurations."""
    result = await db.execute(_scoped_camera_query(user).order_by(CameraConfig.created_at.desc()))
    return result.scalars().all()


@router.post("/configs", response_model=CameraConfigResponse, status_code=201)
async def create_camera_config(
    config: CameraConfigCreate,
    user: UserAccount = Depends(require_roles("admin", "caregiver")),
    db: AsyncSession = Depends(get_db),
):
    """Save a new camera configuration."""
    await _validate_patient_scope(config.patient_id, user, db)
    db_config = CameraConfig(**config.model_dump())
    db.add(db_config)
    await db.commit()
    await db.refresh(db_config)
    return db_config


@router.get("/configs/{config_id}", response_model=CameraConfigResponse)
async def get_camera_config(
    config_id: int,
    user: UserAccount = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get a specific camera configuration."""
    result = await db.execute(_scoped_camera_query(user).where(CameraConfig.id == config_id))
    config = result.scalar_one_or_none()
    if not config:
        raise HTTPException(status_code=404, detail="Camera configuration not found")
    return config


@router.patch("/configs/{config_id}", response_model=CameraConfigResponse)
async def update_camera_config(
    config_id: int,
    update_data: CameraConfigUpdate,
    user: UserAccount = Depends(require_roles("admin", "caregiver")),
    db: AsyncSession = Depends(get_db),
):
    """Update camera configuration metadata and defaults."""
    result = await db.execute(_scoped_camera_query(user).where(CameraConfig.id == config_id))
    config = result.scalar_one_or_none()
    if not config:
        raise HTTPException(status_code=404, detail="Camera configuration not found")

    update_dict = update_data.model_dump(exclude_unset=True)
    if "patient_id" in update_dict:
        await _validate_patient_scope(update_dict.get("patient_id"), user, db)
    for key, value in update_dict.items():
        setattr(config, key, value)

    await db.commit()
    await db.refresh(config)
    return config


@router.delete("/configs/{config_id}", status_code=204)
async def delete_camera_config(
    config_id: int,
    user: UserAccount = Depends(require_roles("admin", "caregiver")),
    db: AsyncSession = Depends(get_db),
):
    """Delete a camera configuration."""
    result = await db.execute(_scoped_camera_query(user).where(CameraConfig.id == config_id))
    config = result.scalar_one_or_none()
    if not config:
        raise HTTPException(status_code=404, detail="Camera configuration not found")
    await db.delete(config)
    await db.commit()


@router.get("/sources")
async def get_supported_sources():
    """Return list of supported camera source types."""
    return {
        "sources": [
            {"type": "usb", "description": "USB webcam", "example": "0 or /dev/video0"},
            {"type": "rtsp", "description": "IP camera RTSP stream", "example": "rtsp://192.168.1.100:554/stream"},
            {"type": "http", "description": "IP camera HTTP stream", "example": "http://192.168.1.100:8080/video"},
            {"type": "video_file", "description": "Pre-recorded video file", "example": "/videos/sample.mp4"},
        ]
    }

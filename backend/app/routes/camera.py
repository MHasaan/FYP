"""
Camera management routes
"""

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.database import get_db
from app.models import CameraConfig
from app.schemas import CameraConfigCreate, CameraConfigResponse, CameraConfigUpdate, CameraSourceRequest

router = APIRouter(prefix="/api/camera", tags=["Camera"])


@router.get("/configs", response_model=list[CameraConfigResponse])
async def list_camera_configs(db: AsyncSession = Depends(get_db)):
    """List all saved camera configurations."""
    result = await db.execute(select(CameraConfig).order_by(CameraConfig.created_at.desc()))
    return result.scalars().all()


@router.post("/configs", response_model=CameraConfigResponse, status_code=201)
async def create_camera_config(config: CameraConfigCreate, db: AsyncSession = Depends(get_db)):
    """Save a new camera configuration."""
    db_config = CameraConfig(**config.model_dump())
    db.add(db_config)
    await db.commit()
    await db.refresh(db_config)
    return db_config


@router.get("/configs/{config_id}", response_model=CameraConfigResponse)
async def get_camera_config(config_id: int, db: AsyncSession = Depends(get_db)):
    """Get a specific camera configuration."""
    result = await db.execute(select(CameraConfig).where(CameraConfig.id == config_id))
    config = result.scalar_one_or_none()
    if not config:
        raise HTTPException(status_code=404, detail="Camera configuration not found")
    return config


@router.patch("/configs/{config_id}", response_model=CameraConfigResponse)
async def update_camera_config(
    config_id: int,
    update_data: CameraConfigUpdate,
    db: AsyncSession = Depends(get_db),
):
    """Update camera configuration metadata and defaults."""
    result = await db.execute(select(CameraConfig).where(CameraConfig.id == config_id))
    config = result.scalar_one_or_none()
    if not config:
        raise HTTPException(status_code=404, detail="Camera configuration not found")

    update_dict = update_data.model_dump(exclude_unset=True)
    for key, value in update_dict.items():
        setattr(config, key, value)

    await db.commit()
    await db.refresh(config)
    return config


@router.delete("/configs/{config_id}", status_code=204)
async def delete_camera_config(config_id: int, db: AsyncSession = Depends(get_db)):
    """Delete a camera configuration."""
    result = await db.execute(select(CameraConfig).where(CameraConfig.id == config_id))
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

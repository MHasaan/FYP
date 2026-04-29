"""
ROI zone management routes.
"""

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models import CameraConfig, ROIZone
from app.schemas import ROIZoneCreate, ROIZoneResponse, ROIZoneUpdate


router = APIRouter(prefix="/api/roi", tags=["ROI Zones"])


@router.get("/zones", response_model=list[ROIZoneResponse])
async def list_roi_zones(
    camera_config_id: int | None = Query(default=None),
    include_inactive: bool = Query(default=True),
    db: AsyncSession = Depends(get_db),
):
    query = select(ROIZone)
    if camera_config_id is not None:
        query = query.where(ROIZone.camera_config_id == camera_config_id)
    if not include_inactive:
        query = query.where(ROIZone.is_active.is_(True))

    query = query.order_by(ROIZone.created_at.desc())
    result = await db.execute(query)
    return result.scalars().all()


@router.post("/zones", response_model=ROIZoneResponse, status_code=status.HTTP_201_CREATED)
async def create_roi_zone(payload: ROIZoneCreate, db: AsyncSession = Depends(get_db)):
    camera_result = await db.execute(
        select(CameraConfig.id).where(CameraConfig.id == payload.camera_config_id)
    )
    if camera_result.scalar_one_or_none() is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Camera config {payload.camera_config_id} not found",
        )

    db_zone = ROIZone(
        camera_config_id=payload.camera_config_id,
        name=payload.name,
        description=payload.description,
        zone_type=payload.zone_type,
        coordinates=payload.coordinates,
        color=payload.color,
        trigger_on_enter=payload.trigger_on_enter,
        trigger_on_exit=payload.trigger_on_exit,
        trigger_on_stay=payload.trigger_on_stay,
        stay_threshold_seconds=payload.stay_threshold_seconds,
    )
    db.add(db_zone)
    await db.commit()
    await db.refresh(db_zone)
    return db_zone


@router.patch("/zones/{zone_id}", response_model=ROIZoneResponse)
async def update_roi_zone(
    zone_id: int,
    payload: ROIZoneUpdate,
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(ROIZone).where(ROIZone.id == zone_id))
    zone = result.scalar_one_or_none()
    if zone is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="ROI zone not found")

    update_data = payload.model_dump(exclude_unset=True)
    for key, value in update_data.items():
        setattr(zone, key, value)

    await db.commit()
    await db.refresh(zone)
    return zone


@router.delete("/zones/{zone_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_roi_zone(zone_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(ROIZone).where(ROIZone.id == zone_id))
    zone = result.scalar_one_or_none()
    if zone is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="ROI zone not found")

    await db.delete(zone)
    await db.commit()

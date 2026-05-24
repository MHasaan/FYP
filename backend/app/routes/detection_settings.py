"""
Detector threshold and enablement routes.
"""

from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models import DetectionSetting, UserAccount
from app.schemas import DetectionSettingCreate, DetectionSettingResponse, DetectionSettingUpdate
from app.services.auth_service import get_current_user, require_roles


router = APIRouter(prefix="/api/detection-settings", tags=["Detection Settings"])


# A detection setting with both camera_config_id and patient_id NULL is the
# *global default* — it applies to anything that doesn't have a per-patient or
# per-camera override. Only one global rule is meaningful at a time, so on
# creation we update the existing one rather than spawning duplicates.


@router.get("/", response_model=list[DetectionSettingResponse])
async def list_detection_settings(
    camera_config_id: Optional[int] = Query(None),
    patient_id: Optional[int] = Query(None),
    _: UserAccount = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """List detector thresholds/toggles for cameras or patients."""
    query = select(DetectionSetting)
    if camera_config_id is not None:
        query = query.where(DetectionSetting.camera_config_id == camera_config_id)
    if patient_id is not None:
        query = query.where(DetectionSetting.patient_id == patient_id)

    result = await db.execute(query.order_by(DetectionSetting.created_at.desc()))
    return result.scalars().all()


@router.post("/", response_model=DetectionSettingResponse, status_code=status.HTTP_201_CREATED)
async def create_detection_setting(
    payload: DetectionSettingCreate,
    _: UserAccount = Depends(require_roles("admin", "caregiver")),
    db: AsyncSession = Depends(get_db),
):
    """Create detector settings for a camera, patient, or global default."""
    data = payload.model_dump()
    camera_id = data.get("camera_config_id")
    patient_id = data.get("patient_id")

    # Global rule (both null): upsert — update the existing one if there is
    # one, otherwise create. Avoids accidental duplicates.
    if camera_id is None and patient_id is None:
        existing = await db.execute(
            select(DetectionSetting).where(
                DetectionSetting.camera_config_id.is_(None),
                DetectionSetting.patient_id.is_(None),
            ).limit(1)
        )
        existing_row = existing.scalar_one_or_none()
        if existing_row is not None:
            for key, value in data.items():
                setattr(existing_row, key, value)
            await db.commit()
            await db.refresh(existing_row)
            return existing_row

    setting = DetectionSetting(**data)
    db.add(setting)
    await db.commit()
    await db.refresh(setting)
    return setting


@router.patch("/{setting_id}", response_model=DetectionSettingResponse)
async def update_detection_setting(
    setting_id: int,
    payload: DetectionSettingUpdate,
    _: UserAccount = Depends(require_roles("admin", "caregiver")),
    db: AsyncSession = Depends(get_db),
):
    """Update detector settings."""
    result = await db.execute(select(DetectionSetting).where(DetectionSetting.id == setting_id))
    setting = result.scalar_one_or_none()
    if setting is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Detection setting not found")

    updates = payload.model_dump(exclude_unset=True)

    for key, value in updates.items():
        setattr(setting, key, value)

    await db.commit()
    await db.refresh(setting)
    return setting


@router.delete("/{setting_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_detection_setting(
    setting_id: int,
    _: UserAccount = Depends(require_roles("admin", "caregiver")),
    db: AsyncSession = Depends(get_db),
):
    """Delete detector settings."""
    result = await db.execute(select(DetectionSetting).where(DetectionSetting.id == setting_id))
    setting = result.scalar_one_or_none()
    if setting is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Detection setting not found")
    await db.delete(setting)
    await db.commit()

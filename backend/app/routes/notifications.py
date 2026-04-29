"""
Push notification device token management routes.
"""

from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models import DeviceToken
from app.schemas import (
    DeviceTokenCreate,
    DeviceTokenResponse,
    DeviceTokenUpdate,
    PushNotificationTestRequest,
    PushNotificationTestResponse,
)


router = APIRouter(prefix="/api/notifications", tags=["Push Notifications"])


@router.get("/devices", response_model=list[DeviceTokenResponse])
async def list_devices(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(DeviceToken).order_by(DeviceToken.created_at.desc()))
    return result.scalars().all()


@router.post("/devices", response_model=DeviceTokenResponse, status_code=status.HTTP_201_CREATED)
async def register_device(payload: DeviceTokenCreate, db: AsyncSession = Depends(get_db)):
    existing_result = await db.execute(
        select(DeviceToken).where(DeviceToken.device_token == payload.device_token)
    )
    existing = existing_result.scalar_one_or_none()

    if existing:
        existing.platform = payload.platform
        existing.user_id = payload.user_id
        existing.device_name = payload.device_name
        existing.is_active = True
        existing.last_used_at = datetime.now(timezone.utc)
        await db.commit()
        await db.refresh(existing)
        return existing

    db_token = DeviceToken(
        device_token=payload.device_token,
        platform=payload.platform,
        user_id=payload.user_id,
        device_name=payload.device_name,
        is_active=True,
        last_used_at=datetime.now(timezone.utc),
    )
    db.add(db_token)
    await db.commit()
    await db.refresh(db_token)
    return db_token


@router.patch("/devices/{device_id}", response_model=DeviceTokenResponse)
async def update_device(device_id: int, payload: DeviceTokenUpdate, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(DeviceToken).where(DeviceToken.id == device_id))
    device = result.scalar_one_or_none()
    if not device:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Device token not found")

    updates = payload.model_dump(exclude_unset=True)
    for key, value in updates.items():
        setattr(device, key, value)

    device.last_used_at = datetime.now(timezone.utc)
    await db.commit()
    await db.refresh(device)
    return device


@router.delete("/devices/{device_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_device(device_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(DeviceToken).where(DeviceToken.id == device_id))
    device = result.scalar_one_or_none()
    if not device:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Device token not found")

    await db.delete(device)
    await db.commit()


@router.post("/test", response_model=PushNotificationTestResponse)
async def send_test_notification(payload: PushNotificationTestRequest, db: AsyncSession = Depends(get_db)):
    query = select(DeviceToken).where(DeviceToken.is_active == True)  # noqa: E712
    if payload.platform:
        query = query.where(DeviceToken.platform == payload.platform)
    if payload.user_id:
        query = query.where(DeviceToken.user_id == payload.user_id)

    result = await db.execute(query)
    recipients = result.scalars().all()

    now = datetime.now(timezone.utc)
    for recipient in recipients:
        recipient.last_used_at = now

    await db.commit()

    return PushNotificationTestResponse(
        sent_to=len(recipients),
        platform=payload.platform,
        user_id=payload.user_id,
        simulated=True,
        message=(
            "Simulated push dispatch complete. "
            "Integrate FCM/APNS provider credentials to send real mobile notifications."
        ),
    )

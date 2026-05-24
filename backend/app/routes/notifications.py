"""
Push notification device token management routes.

All device-token endpoints are scoped to the current authenticated user. A
caregiver can't list/modify/delete another caregiver's tokens, and the
`user_id` field of a registration is bound server-side to the caller rather
than being honoured from the request body (which would let any client
register tokens against arbitrary users and intercept their notifications).
"""

from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models import DeviceToken, UserAccount
from app.schemas import (
    DeviceTokenCreate,
    DeviceTokenResponse,
    DeviceTokenUpdate,
    PushNotificationTestRequest,
    PushNotificationTestResponse,
)
from app.services import push_service
from app.services.auth_service import get_current_user, require_roles


router = APIRouter(prefix="/api/notifications", tags=["Push Notifications"])


@router.get("/devices", response_model=list[DeviceTokenResponse])
async def list_devices(
    user: UserAccount = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """List the *current user's* registered devices. Admins see all devices."""
    query = select(DeviceToken).order_by(DeviceToken.created_at.desc())
    if user.role != "admin":
        query = query.where(DeviceToken.user_id == user.id)
    result = await db.execute(query)
    return result.scalars().all()


@router.post("/devices", response_model=DeviceTokenResponse, status_code=status.HTTP_201_CREATED)
async def register_device(
    payload: DeviceTokenCreate,
    user: UserAccount = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Register a push token for the current user.

    The `user_id` field on the payload is ignored — we always bind the
    registration to the caller. This prevents a malicious client from
    registering its own device token against another user's ID and
    intercepting their notifications.
    """
    existing_result = await db.execute(
        select(DeviceToken).where(DeviceToken.device_token == payload.device_token)
    )
    existing = existing_result.scalar_one_or_none()

    if existing:
        existing.platform = payload.platform
        existing.user_id = user.id
        existing.device_name = payload.device_name
        existing.is_active = True
        existing.last_used_at = datetime.now(timezone.utc)
        await db.commit()
        await db.refresh(existing)
        return existing

    db_token = DeviceToken(
        device_token=payload.device_token,
        platform=payload.platform,
        user_id=user.id,
        device_name=payload.device_name,
        is_active=True,
        last_used_at=datetime.now(timezone.utc),
    )
    db.add(db_token)
    await db.commit()
    await db.refresh(db_token)
    return db_token


async def _get_own_device(
    device_id: int, user: UserAccount, db: AsyncSession
) -> DeviceToken:
    """Fetch a device by id, but only if it belongs to the caller (or caller is admin)."""
    result = await db.execute(select(DeviceToken).where(DeviceToken.id == device_id))
    device = result.scalar_one_or_none()
    if not device:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Device token not found")
    if user.role != "admin" and device.user_id != user.id:
        # Same response shape as missing — don't leak existence to non-owners.
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Device token not found")
    return device


@router.patch("/devices/{device_id}", response_model=DeviceTokenResponse)
async def update_device(
    device_id: int,
    payload: DeviceTokenUpdate,
    user: UserAccount = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    device = await _get_own_device(device_id, user, db)

    updates = payload.model_dump(exclude_unset=True)
    # Don't let a non-admin reassign a device to a different user.
    if user.role != "admin":
        updates.pop("user_id", None)
    for key, value in updates.items():
        setattr(device, key, value)

    device.last_used_at = datetime.now(timezone.utc)
    await db.commit()
    await db.refresh(device)
    return device


@router.delete("/devices/{device_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_device(
    device_id: int,
    user: UserAccount = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    device = await _get_own_device(device_id, user, db)
    await db.delete(device)
    await db.commit()


@router.post("/test", response_model=PushNotificationTestResponse)
async def send_test_notification(
    payload: PushNotificationTestRequest,
    user: UserAccount = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Send a test push notification.

    Non-admins can only send a test to *their own* devices. Admins can
    target a specific user_id or platform.
    """
    query = select(DeviceToken).where(DeviceToken.is_active == True)  # noqa: E712
    if payload.platform:
        query = query.where(DeviceToken.platform == payload.platform)
    if user.role == "admin":
        if payload.user_id:
            query = query.where(DeviceToken.user_id == payload.user_id)
    else:
        # Force scope to self regardless of payload.user_id
        query = query.where(DeviceToken.user_id == user.id)

    result = await db.execute(query)
    recipients = list(result.scalars().all())

    now = datetime.now(timezone.utc)
    for recipient in recipients:
        recipient.last_used_at = now
    await db.commit()

    fcm_tokens = [t for t in recipients if t.platform == "fcm"]
    dispatch_result = await push_service.dispatch_test(
        db,
        fcm_tokens,
        title=payload.title or "Eldercare test notification",
        body=payload.body or "Real-time alerting is wired up.",
    )

    simulated = bool(dispatch_result.get("simulated"))
    sent_to = int(dispatch_result.get("sent_to") or 0)
    if simulated:
        sent_to = len(recipients)
        message = (
            "Simulated push dispatch complete. "
            "Set FCM_CREDENTIALS_PATH to enable real delivery."
        )
    elif dispatch_result.get("error"):
        message = f"FCM error: {dispatch_result['error']}"
    elif sent_to == 0:
        message = "No FCM-capable devices were registered for the requested filter."
    else:
        failed = int(dispatch_result.get("failed") or 0)
        message = f"Push delivered to {sent_to} device(s)."
        if failed:
            message += f" {failed} failed and were marked inactive."

    return PushNotificationTestResponse(
        sent_to=sent_to,
        platform=payload.platform,
        user_id=payload.user_id if user.role == "admin" else user.id,
        simulated=simulated,
        message=message,
    )

"""
Firebase Cloud Messaging dispatcher.

Sends push notifications to mobile (Android / iOS) devices registered in the
`device_tokens` table. Falls back to simulation mode when FCM credentials are
not configured, so dev environments still boot without Firebase setup.
"""
from __future__ import annotations

import logging
from typing import Iterable, Optional

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.models import DeviceToken, PatientProfile, UserAccount

logger = logging.getLogger(__name__)
_settings = get_settings()
_initialized: bool = False
_fcm_available: bool = False


def _ensure_initialized() -> bool:
    """Lazy-initialize firebase_admin once. Returns True when real FCM is wired."""
    global _initialized, _fcm_available
    if _initialized:
        return _fcm_available

    _initialized = True
    creds_path = (_settings.fcm_credentials_path or "").strip()
    if not creds_path:
        logger.warning(
            "FCM_CREDENTIALS_PATH not set — push dispatch will run in simulation mode"
        )
        _fcm_available = False
        return False

    try:
        import firebase_admin
        from firebase_admin import credentials

        # Re-using the default app is allowed when the module is reloaded.
        if not firebase_admin._apps:  # type: ignore[attr-defined]
            cred = credentials.Certificate(creds_path)
            firebase_admin.initialize_app(cred)
        _fcm_available = True
        logger.info("Firebase Admin initialized for FCM push dispatch")
        return True
    except FileNotFoundError:
        logger.error(
            "FCM credentials file not found at %s — push dispatch will be simulated",
            creds_path,
        )
        _fcm_available = False
        return False
    except Exception as exc:  # pragma: no cover - boot-time guard
        logger.exception("Failed to initialize Firebase Admin: %s", exc)
        _fcm_available = False
        return False


async def _resolve_target_user_ids(
    db: AsyncSession, patient_id: Optional[int]
) -> list[int]:
    """Return the user IDs that should receive a push for this incident.

    Always includes every active admin. Adds the patient's caregiver and
    relative when a patient_id is supplied.
    """
    user_ids: set[int] = set()
    admin_result = await db.execute(
        select(UserAccount.id).where(
            UserAccount.role == "admin",
            UserAccount.is_active == True,  # noqa: E712
        )
    )
    user_ids.update(int(uid) for uid in admin_result.scalars().all())

    if patient_id is not None:
        patient_result = await db.execute(
            select(PatientProfile).where(PatientProfile.id == patient_id)
        )
        patient = patient_result.scalar_one_or_none()
        if patient is not None:
            if patient.caregiver_id is not None:
                user_ids.add(int(patient.caregiver_id))
            if patient.relative_user_id is not None:
                user_ids.add(int(patient.relative_user_id))
    return sorted(user_ids)


async def _fetch_active_tokens(
    db: AsyncSession, user_ids: Iterable[int]
) -> list[DeviceToken]:
    user_id_strs = [str(u) for u in user_ids]
    if not user_id_strs:
        return []
    result = await db.execute(
        select(DeviceToken).where(
            DeviceToken.user_id.in_(user_id_strs),
            DeviceToken.platform == "fcm",
            DeviceToken.is_active == True,  # noqa: E712
        )
    )
    return list(result.scalars().all())


async def dispatch_incident(
    db: AsyncSession,
    incident,
    *,
    patient_name: Optional[str] = None,
    camera_name: Optional[str] = None,
) -> dict:
    """Push a freshly-created incident to all relevant caregivers/admins."""
    target_users = await _resolve_target_user_ids(db, incident.patient_id)
    tokens_rows = await _fetch_active_tokens(db, target_users)
    if not tokens_rows:
        return {"sent_to": 0, "simulated": False, "reason": "no_active_tokens"}

    event = (incident.event_type or "alert").upper()
    title = f"{event} detected"
    if patient_name:
        title += f" — {patient_name}"
    body = camera_name or "New incident"

    data = {
        "incident_id": str(incident.id),
        "patient_id": str(incident.patient_id or ""),
        "event_type": str(incident.event_type or ""),
        "severity": str(incident.severity or ""),
        "click_action": "FLUTTER_NOTIFICATION_CLICK",
        "type": "incident",
    }
    return await _send(db, tokens_rows, title, body, data)


async def dispatch_test(
    db: AsyncSession,
    tokens_rows: list[DeviceToken],
    title: str,
    body: str,
) -> dict:
    return await _send(
        db,
        tokens_rows,
        title,
        body,
        {"type": "test", "click_action": "FLUTTER_NOTIFICATION_CLICK"},
    )


async def _send(
    db: AsyncSession,
    tokens_rows: list[DeviceToken],
    title: str,
    body: str,
    data: dict,
) -> dict:
    if not tokens_rows:
        return {"sent_to": 0, "simulated": False, "reason": "no_targets"}

    if not _ensure_initialized():
        # Simulation: just touch last_used_at and return.
        return {
            "sent_to": len(tokens_rows),
            "simulated": True,
            "message": (
                "Simulated push dispatch complete. "
                "Set FCM_CREDENTIALS_PATH to enable real delivery."
            ),
        }

    from firebase_admin import messaging

    tokens = [t.device_token for t in tokens_rows]
    str_data = {k: str(v) for k, v in data.items() if v is not None}
    message = messaging.MulticastMessage(
        tokens=tokens,
        notification=messaging.Notification(title=title, body=body),
        data=str_data,
        android=messaging.AndroidConfig(
            priority="high",
            notification=messaging.AndroidNotification(
                icon=_settings.fcm_default_icon or None,
                channel_id="eldercare_alerts",
                click_action="FLUTTER_NOTIFICATION_CLICK",
            ),
        ),
    )

    try:
        # send_each_for_multicast is the preferred sync API in firebase-admin>=6.2;
        # it transparently fans out to send_each.
        response = messaging.send_each_for_multicast(message)
    except Exception as exc:  # pragma: no cover
        logger.error("FCM send failed: %s", exc)
        return {"sent_to": 0, "simulated": False, "error": str(exc)}

    invalid_token_ids: list[int] = []
    for token_row, single in zip(tokens_rows, response.responses):
        if single.success:
            continue
        err = single.exception
        code = getattr(err, "code", "") if err else ""
        # Mark known-dead tokens as inactive so we stop hitting them.
        if code in {
            "registration-token-not-registered",
            "invalid-argument",
            "invalid-registration-token",
        }:
            invalid_token_ids.append(token_row.id)

    if invalid_token_ids:
        await db.execute(
            update(DeviceToken)
            .where(DeviceToken.id.in_(invalid_token_ids))
            .values(is_active=False)
        )
        await db.commit()

    return {
        "sent_to": response.success_count,
        "failed": response.failure_count,
        "simulated": False,
    }

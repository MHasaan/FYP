"""
Real-time incident broadcast WebSocket endpoint.

Subscribers receive a JSON IncidentEvent payload whenever a new incident is
created. Scoping rules:
- admin            -> receives all incidents
- caregiver        -> receives only incidents for patients assigned to them
- patient_relative -> receives only incidents for patients where they are the relative

The token is passed via the `token` query string because browsers cannot
attach Authorization headers to WebSocket handshakes.
"""

import asyncio
import json
import logging

from fastapi import WebSocket, WebSocketDisconnect
from sqlalchemy import select

from app.database import get_db_context
from app.models import CameraConfig, PatientProfile
from app.services.auth_service import get_user_from_token
from app.services.redis_service import get_redis_client

logger = logging.getLogger(__name__)


async def incidents_ws(websocket: WebSocket, token: str | None = None):
    """WebSocket handler for /ws/incidents."""
    if not token:
        await websocket.close(code=4401, reason="Missing token")
        return

    # Validate token outside of accept() so we can close cleanly on auth fail.
    async with get_db_context() as db:
        user = await get_user_from_token(token, db)

    if user is None:
        await websocket.close(code=4403, reason="Invalid or expired token")
        return

    if user.role not in {"admin", "caregiver", "patient_relative"}:
        await websocket.close(code=4403, reason="Role not permitted")
        return

    await websocket.accept()
    logger.info(f"Incident WS connected: user_id={user.id} role={user.role}")

    redis = await get_redis_client()
    pubsub = redis.pubsub()
    await pubsub.subscribe("incidents:new")

    try:
        while True:
            try:
                message = await asyncio.wait_for(
                    pubsub.get_message(ignore_subscribe_messages=True, timeout=1.0),
                    timeout=30.0,
                )
            except asyncio.TimeoutError:
                # Periodic keepalive so dead sockets surface quickly.
                try:
                    await websocket.send_json({"type": "ping"})
                except Exception:
                    break
                continue

            if not message or not message.get("data"):
                continue

            try:
                data = json.loads(message["data"])
            except (TypeError, ValueError):
                continue

            patient_id = data.get("patient_id")

            # Resolve patient + apply scope filter
            patient = None
            if patient_id is not None:
                async with get_db_context() as db:
                    result = await db.execute(
                        select(PatientProfile).where(PatientProfile.id == patient_id)
                    )
                    patient = result.scalar_one_or_none()

            if user.role == "caregiver":
                if patient is None or patient.caregiver_id != user.id:
                    continue
            elif user.role == "patient_relative":
                if patient is None or patient.relative_user_id != user.id:
                    continue
            # admin: no filter

            data["patient_name"] = patient.full_name if patient else None

            # Resolve camera name (best-effort)
            camera_id = data.get("camera_config_id")
            if camera_id is not None:
                async with get_db_context() as db:
                    cam_result = await db.execute(
                        select(CameraConfig).where(CameraConfig.id == camera_id)
                    )
                    cam = cam_result.scalar_one_or_none()
                    data["camera_name"] = cam.name if cam else None
            else:
                data["camera_name"] = None

            data["type"] = "incident"
            try:
                await websocket.send_json(data)
            except Exception as e:
                logger.warning(f"Incident WS send failed: {e}")
                break
    except WebSocketDisconnect:
        pass
    except Exception as e:
        logger.exception(f"Incident WS error: {e}")
    finally:
        try:
            await pubsub.unsubscribe("incidents:new")
            await pubsub.close()
        except Exception:
            pass
        logger.info(f"Incident WS disconnected: user_id={user.id}")

"""
Webhook management routes.
"""

import asyncio
import hashlib
import hmac
import json
from datetime import datetime, timezone
from urllib import request as urllib_request
from urllib.error import URLError, HTTPError

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models import Webhook
from app.schemas import WebhookCreate, WebhookUpdate, WebhookResponse, WebhookTestRequest


router = APIRouter(prefix="/api/webhooks", tags=["Webhooks"])


@router.get("/", response_model=list[WebhookResponse])
async def list_webhooks(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Webhook).order_by(Webhook.created_at.desc()))
    return result.scalars().all()


@router.post("/", response_model=WebhookResponse, status_code=status.HTTP_201_CREATED)
async def create_webhook(payload: WebhookCreate, db: AsyncSession = Depends(get_db)):
    db_webhook = Webhook(
        name=payload.name,
        url=payload.url,
        secret_key=payload.secret_key,
        headers=payload.headers,
        events=payload.events,
        retry_count=payload.retry_count,
    )
    db.add(db_webhook)
    await db.commit()
    await db.refresh(db_webhook)
    return db_webhook


@router.patch("/{webhook_id}", response_model=WebhookResponse)
async def update_webhook(
    webhook_id: int,
    payload: WebhookUpdate,
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Webhook).where(Webhook.id == webhook_id))
    webhook = result.scalar_one_or_none()
    if not webhook:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Webhook not found")

    updates = payload.model_dump(exclude_unset=True)
    for key, value in updates.items():
        setattr(webhook, key, value)

    await db.commit()
    await db.refresh(webhook)
    return webhook


@router.delete("/{webhook_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_webhook(webhook_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Webhook).where(Webhook.id == webhook_id))
    webhook = result.scalar_one_or_none()
    if not webhook:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Webhook not found")

    await db.delete(webhook)
    await db.commit()


def _post_json(url: str, payload: dict, headers: dict, timeout_seconds: int = 5):
    body_bytes = json.dumps(payload).encode("utf-8")
    req = urllib_request.Request(url=url, method="POST", data=body_bytes)
    req.add_header("Content-Type", "application/json")
    for key, value in headers.items():
        req.add_header(str(key), str(value))

    with urllib_request.urlopen(req, timeout=timeout_seconds) as response:
        return response.status


@router.post("/test")
async def test_webhook(payload: WebhookTestRequest, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Webhook).where(Webhook.id == payload.webhook_id))
    webhook = result.scalar_one_or_none()
    if not webhook:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Webhook not found")

    test_payload = {
        "event": "webhook.test",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "data": {
            "message": "Webhook test event from FYP backend",
            "webhook_id": webhook.id,
            "webhook_name": webhook.name,
        },
    }

    outbound_headers = dict(webhook.headers or {})
    if webhook.secret_key:
        signature = hmac.new(
            webhook.secret_key.encode("utf-8"),
            msg=json.dumps(test_payload).encode("utf-8"),
            digestmod=hashlib.sha256,
        ).hexdigest()
        outbound_headers["X-FYP-Signature"] = signature

    status_code = None
    error_message = None
    for attempt in range(max(1, int(webhook.retry_count or 1))):
        try:
            status_code = await asyncio.to_thread(_post_json, webhook.url, test_payload, outbound_headers)
            break
        except HTTPError as exc:
            status_code = exc.code
            error_message = str(exc)
        except URLError as exc:
            error_message = str(exc)
        except Exception as exc:  # defensive
            error_message = str(exc)

    webhook.last_called_at = datetime.now(timezone.utc)
    webhook.last_status_code = status_code
    if status_code is None or status_code >= 400:
        webhook.failure_count = int(webhook.failure_count or 0) + 1
    await db.commit()

    if status_code is None or status_code >= 400:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail={
                "message": "Webhook test failed",
                "status_code": status_code,
                "error": error_message,
            },
        )

    return {
        "message": "Webhook test delivered",
        "status_code": status_code,
        "webhook_id": webhook.id,
    }

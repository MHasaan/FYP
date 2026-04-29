"""
WebSocket handler for live video feed streaming to frontend.
Subscribes to Redis channel where ML Manager publishes annotated frames.
"""

import asyncio
import json
import base64
import redis.asyncio as aioredis
from fastapi import WebSocket, WebSocketDisconnect
from app.config import get_settings

settings = get_settings()

# Channel where ML Manager publishes annotated frames (JPEG bytes as base64)
FRAME_CHANNEL = "pipeline:frames"


async def feed_websocket(websocket: WebSocket):
    """
    WebSocket endpoint that streams live video frames to the frontend.
    Each message is a JSON object: {"frame_id": int, "image": "base64_jpeg_data"}
    """
    await websocket.accept()

    redis = aioredis.from_url(settings.redis_url, decode_responses=True)
    pubsub = redis.pubsub()
    await pubsub.subscribe(FRAME_CHANNEL)

    try:
        while True:
            message = await pubsub.get_message(ignore_subscribe_messages=True, timeout=1.0)
            if message and message["type"] == "message":
                await websocket.send_text(message["data"])
            else:
                # Small sleep to prevent busy waiting
                await asyncio.sleep(0.01)
    except WebSocketDisconnect:
        pass
    except Exception as e:
        print(f"Feed WebSocket error: {e}")
    finally:
        await pubsub.unsubscribe(FRAME_CHANNEL)
        await pubsub.close()
        await redis.close()

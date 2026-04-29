"""
WebSocket handler for real-time ML results streaming to frontend.
Subscribes to Redis channel where ML Manager publishes detection results.
"""

import asyncio
import json
import redis.asyncio as aioredis
from fastapi import WebSocket, WebSocketDisconnect
from app.config import get_settings

settings = get_settings()

# Channel where ML Manager publishes aggregated frame results
RESULTS_CHANNEL = "pipeline:results"


async def results_websocket(websocket: WebSocket):
    """
    WebSocket endpoint that streams real-time ML results to the frontend.
    Each message is a JSON object with all model results for a single frame:
    {
        "frame_id": 123,
        "timestamp": "...",
        "results": {
            "pose": {...},
            "yolo": {...},
            "custom_model_1": {...},
            "custom_model_2": {...}
        },
        "total_processing_time_ms": 45.2
    }
    """
    await websocket.accept()

    redis = aioredis.from_url(settings.redis_url, decode_responses=True)
    pubsub = redis.pubsub()
    await pubsub.subscribe(RESULTS_CHANNEL)

    try:
        while True:
            message = await pubsub.get_message(ignore_subscribe_messages=True, timeout=1.0)
            if message and message["type"] == "message":
                await websocket.send_text(message["data"])
            else:
                await asyncio.sleep(0.01)
    except WebSocketDisconnect:
        pass
    except Exception as e:
        print(f"Results WebSocket error: {e}")
    finally:
        await pubsub.unsubscribe(RESULTS_CHANNEL)
        await pubsub.close()
        await redis.close()

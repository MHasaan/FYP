"""
WebSocket handler for instance-specific ML results streaming to frontend.
Subscribes to instance-specific Redis channels where ML Manager publishes results.
"""

import asyncio
import json
import redis.asyncio as aioredis
from fastapi import WebSocket, WebSocketDisconnect
from app.config import get_settings

settings = get_settings()


async def instance_results_websocket(websocket: WebSocket, instance_id: int):
    """
    WebSocket endpoint that streams real-time ML results for a specific pipeline instance.
    Each message is a JSON object with all model results for a single frame:
    {
        "frame_id": 123,
        "instance_id": 1,
        "timestamp": "...",
        "results": {
            "pose": {...},
            "yolo": {...}
        },
        "timing": {
            "pose": 25.3,
            "yolo": 19.8
        },
        "total_processing_time_ms": 45.2
    }
    """
    await websocket.accept()

    # Subscribe to instance-specific results channel
    results_channel = f"pipeline:{instance_id}:results"

    redis = aioredis.from_url(settings.redis_url, decode_responses=True)
    pubsub = redis.pubsub()
    await pubsub.subscribe(results_channel)

    try:
        while True:
            message = await pubsub.get_message(ignore_subscribe_messages=True, timeout=1.0)
            if message and message["type"] == "message":
                try:
                    # Parse the message and add instance_id for frontend identification
                    data = json.loads(message["data"])
                    data["instance_id"] = instance_id
                    await websocket.send_text(json.dumps(data))
                except json.JSONDecodeError:
                    # Send raw data if not JSON
                    await websocket.send_text(message["data"])
            else:
                await asyncio.sleep(0.01)
    except WebSocketDisconnect:
        pass
    except Exception as e:
        print(f"Instance {instance_id} results WebSocket error: {e}")
    finally:
        await pubsub.unsubscribe(results_channel)
        await pubsub.close()
        await redis.close()
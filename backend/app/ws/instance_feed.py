"""
WebSocket handler for instance-specific video feed streaming to frontend.
Subscribes to instance-specific Redis channels where ML Manager publishes frames.
"""

import asyncio
import json
import redis.asyncio as aioredis
from fastapi import WebSocket, WebSocketDisconnect
from app.config import get_settings

settings = get_settings()


async def instance_feed_websocket(websocket: WebSocket, instance_id: int):
    """
    WebSocket endpoint that streams live video frames for a specific pipeline instance.
    Each message is a JSON object: {"frame_id": int, "image": "base64_jpeg_data", "instance_id": int}
    """
    await websocket.accept()

    # Subscribe to instance-specific frame channel
    frame_channel = f"pipeline:{instance_id}:frames"

    redis = aioredis.from_url(settings.redis_url, decode_responses=True)
    pubsub = redis.pubsub()
    await pubsub.subscribe(frame_channel)

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
                # Small sleep to prevent busy waiting
                await asyncio.sleep(0.01)
    except WebSocketDisconnect:
        pass
    except Exception as e:
        print(f"Instance {instance_id} feed WebSocket error: {e}")
    finally:
        await pubsub.unsubscribe(frame_channel)
        await pubsub.close()
        await redis.close()
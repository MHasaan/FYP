"""
Redis Service - Helper for Redis connections
"""

import os
from typing import Optional
import redis.asyncio as redis


_redis_client: Optional[redis.Redis] = None


async def get_redis_client() -> redis.Redis:
    """
    Get or create a Redis client connection.

    Returns a singleton Redis client for async operations.
    """
    global _redis_client

    if _redis_client is None:
        redis_url = os.environ.get("REDIS_URL", "redis://redis:6379/0")
        _redis_client = await redis.from_url(
            redis_url,
            encoding="utf-8",
            decode_responses=True,
        )

    return _redis_client


async def close_redis_client():
    """Close the Redis client connection."""
    global _redis_client

    if _redis_client:
        await _redis_client.close()
        _redis_client = None

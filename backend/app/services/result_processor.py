"""
Result Processor Service
Listens to ML results from Redis, saves them to the database,
and evaluates alert rules.
"""

import asyncio
import json
import time
from datetime import datetime, timezone
from typing import Optional, Any

import redis.asyncio as aioredis
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.database import async_session
from app.models import DetectionResult, Session, AlertRule, ActivityLog, PipelineInstance
from app.services.activity_logger import log_event

settings = get_settings()


class ResultProcessor:
    """
    Background service that processes ML results from Redis.
    - Saves detections to the database
    - Evaluates alert rules
    - Updates session/instance stats
    """

    def __init__(self):
        self._running = False
        self._task: Optional[asyncio.Task] = None
        self._redis: Optional[aioredis.Redis] = None
        self._last_alert_time: dict[int, float] = {}  # rule_id -> timestamp

    async def start(self):
        """Start the background processing task."""
        if self._running:
            return
        
        self._running = True
        self._redis = await aioredis.from_url(settings.redis_url, decode_responses=True)
        self._task = asyncio.create_task(self._run_loop())
        print("🚀 Result Processor started")

    async def stop(self):
        """Stop the background processing task."""
        self._running = False
        if self._task:
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass
        
        if self._redis:
            await self._redis.close()
            self._redis = None
        
        print("🛑 Result Processor stopped")

    async def _run_loop(self):
        """Main loop listening for Redis messages."""
        pubsub = self._redis.pubsub()
        # Listen to all instance-specific results
        await pubsub.psubscribe("pipeline:*:results")
        
        print("📡 Listening for ML results on 'pipeline:*:results'...")

        while self._running:
            try:
                message = await pubsub.get_message(ignore_subscribe_messages=True, timeout=1.0)
                if message and message["type"] == "pmessage":
                    await self._handle_message(message["data"])
            except Exception as e:
                print(f"❌ ResultProcessor loop error: {e}")
                await asyncio.sleep(1)
        
        await pubsub.punsubscribe("pipeline:*:results")

    async def _handle_message(self, data_str: str):
        """Process a single result message."""
        try:
            data = json.loads(data_str)
            instance_id = data.get("instance_id")
            session_id = data.get("session_id")
            frame_id = data.get("frame_id")
            results = data.get("results", {})
            timing = data.get("timing", {})

            if not session_id:
                return

            async with async_session() as db:
                # 1. Save detections to database
                await self._save_detections(db, session_id, frame_id, results, timing)
                
                # 2. Update instance stats (frames processed)
                if instance_id:
                    await self._update_instance_stats(db, instance_id)

                # 3. Evaluate alert rules
                await self._evaluate_alerts(db, instance_id, session_id, results)

                await db.commit()

        except Exception as e:
            print(f"⚠️ Error handling result message: {e}")

    async def _save_detections(self, db: AsyncSession, session_id: int, frame_id: int, results: dict, timing: dict):
        """Save results from all models for this frame."""
        for model_name, result_data in results.items():
            # Skip empty or large raw data if necessary
            # For fall_detection, we care about 'is_fall' and 'probability'
            
            confidence = None
            if isinstance(result_data, dict):
                confidence = result_data.get("probability") or result_data.get("confidence")

            detection = DetectionResult(
                session_id=session_id,
                frame_id=frame_id,
                model_name=model_name,
                result_data=result_data,
                confidence=confidence,
                processing_time_ms=timing.get(model_name, 0),
            )
            db.add(detection)

    async def _update_instance_stats(self, db: AsyncSession, instance_id: int):
        """Increment frame count for the instance."""
        await db.execute(
            update(PipelineInstance)
            .where(PipelineInstance.id == instance_id)
            .values(frames_processed=PipelineInstance.frames_processed + 1)
        )

    async def _evaluate_alerts(self, db: AsyncSession, instance_id: Optional[int], session_id: int, results: dict):
        """Check results against active alert rules."""
        # Get all active alert rules for this instance or global
        query = select(AlertRule).where(AlertRule.is_active == True)
        if instance_id:
            query = query.where((AlertRule.pipeline_instance_id == instance_id) | (AlertRule.pipeline_instance_id == None))
        else:
            query = query.where(AlertRule.pipeline_instance_id == None)
        
        result = await db.execute(query)
        rules = result.scalars().all()

        for rule in rules:
            model_name = rule.model_name
            if model_name not in results:
                continue

            model_result = results[model_name]
            condition = rule.trigger_condition  # e.g. {"field": "is_fall", "operator": "==", "value": True}
            
            if self._check_condition(model_result, condition):
                await self._trigger_alert(db, rule, instance_id, session_id, model_result)

    def _check_condition(self, result: Any, condition: dict) -> bool:
        """Evaluate a trigger condition against a result."""
        try:
            # 1. Support for AlertTriggerCondition schema (type, confidence_min, etc.)
            cond_type = condition.get("type")
            if cond_type == "confidence_above":
                # For fall_detection, 'probability' is the confidence field
                conf = result.get("probability") or result.get("confidence", 0)
                target = condition.get("confidence_min", 0)
                return float(conf) >= float(target)
            
            if cond_type == "object_detected":
                # Check if classes exist in result (for YOLO/Pose)
                classes = condition.get("classes", [])
                if not classes: return True
                # Simple check: if model says it's a fall, we consider it a 'detected object'
                if result.get("is_fall"): return True
                return False

            # 2. Support for generic field-based conditions
            field = condition.get("field")
            operator = condition.get("operator", "==")
            target_value = condition.get("value")

            if not field or field not in result:
                # Fallback for simple boolean results if field is empty
                if not field and isinstance(result, bool):
                    val = result
                elif field == "probability" and "confidence" in result:
                    val = result["confidence"]
                else:
                    return False
            else:
                val = result[field]

            if operator == "==": return val == target_value
            if operator == "!=": return val != target_value
            if operator == ">": return float(val) > float(target_value)
            if operator == "<": return float(val) < float(target_value)
            if operator == ">=": return float(val) >= float(target_value)
            if operator == "<=": return float(val) <= float(target_value)
            
            return False
        except Exception as e:
            print(f"⚠️ Error checking condition: {e}")
            return False

    async def _trigger_alert(self, db: AsyncSession, rule: AlertRule, instance_id: Optional[int], session_id: int, result: dict):
        """Execute alert actions and log event."""
        now = time.time()
        
        # Check cooldown
        last_time = self._last_alert_time.get(rule.id, 0)
        if now - last_time < rule.cooldown_seconds:
            return

        self._last_alert_time[rule.id] = now
        
        # 1. Update rule stats
        rule.trigger_count += 1
        rule.last_triggered_at = datetime.now(timezone.utc)

        # 2. Create activity log (this serves as the "Alert" entry)
        message = f"Alert Triggered: {rule.name}"
        if rule.model_name == "fall_detection":
            prob = result.get("probability", 0)
            message = f"⚠ FALL DETECTED (Confidence: {prob:.2f})"

        log = ActivityLog(
            event_type="alert",
            source="ml_manager",
            severity="critical" if rule.model_name == "fall_detection" else "warning",
            message=message,
            pipeline_instance_id=instance_id,
            session_id=session_id,
            extra_data={
                "rule_id": rule.id,
                "rule_name": rule.name,
                "model_name": rule.model_name,
                "detection_data": result
            }
        )
        db.add(log)
        
        print(f"🔔 ALERT: {message}")

        # 3. Actions (e.g. Webhooks) - can be expanded later
        # For now, just printing is enough to verify it works

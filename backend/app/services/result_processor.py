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
from app.models import (
    ActivityLog,
    AlertRule,
    CameraConfig,
    DetectionResult,
    Incident,
    PipelineInstance,
)

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
        self._pending_incident_publishes: list[dict] = []

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

                # 3. Evaluate alert rules (may queue incident publishes)
                self._pending_incident_publishes.clear()
                await self._evaluate_alerts(db, instance_id, session_id, results)

                await db.commit()

            # 4. After successful commit, publish any new incidents to Redis so
            # the /ws/incidents endpoint can fan them out to caregivers.
            if self._pending_incident_publishes and self._redis is not None:
                for payload in self._pending_incident_publishes:
                    try:
                        await self._redis.publish("incidents:new", json.dumps(payload))
                    except Exception as e:
                        print(f"⚠️ Failed to publish incident event: {e}")

                # 5. Dispatch FCM push notifications for the same incidents.
                # Use a fresh session so we can re-fetch patient/camera names
                # and avoid stale ORM state from the committed session above.
                try:
                    await self._dispatch_pushes(self._pending_incident_publishes)
                except Exception as e:
                    print(f"⚠️ Failed to dispatch push notifications: {e}")

                self._pending_incident_publishes.clear()

        except Exception as e:
            print(f"⚠️ Error handling result message: {e}")

    async def _dispatch_pushes(self, payloads: list[dict]):
        """Send a push for each newly-created incident."""
        if not payloads:
            return
        # Local import to avoid pulling firebase_admin into the import chain
        # before configuration is available.
        from app.services import push_service
        from app.models import CameraConfig, PatientProfile

        async with async_session() as db:
            for payload in payloads:
                incident_id = payload.get("id")
                if incident_id is None:
                    continue

                # Re-fetch the incident in this session for the dispatcher.
                inc_result = await db.execute(
                    select(Incident).where(Incident.id == incident_id)
                )
                incident = inc_result.scalar_one_or_none()
                if incident is None:
                    continue

                patient_name = None
                if incident.patient_id is not None:
                    p_result = await db.execute(
                        select(PatientProfile).where(PatientProfile.id == incident.patient_id)
                    )
                    p = p_result.scalar_one_or_none()
                    if p is not None:
                        patient_name = p.full_name

                camera_name = None
                if incident.camera_config_id is not None:
                    c_result = await db.execute(
                        select(CameraConfig).where(CameraConfig.id == incident.camera_config_id)
                    )
                    c = c_result.scalar_one_or_none()
                    if c is not None:
                        camera_name = c.name

                try:
                    await push_service.dispatch_incident(
                        db,
                        incident,
                        patient_name=patient_name,
                        camera_name=camera_name,
                    )
                except Exception as e:
                    print(f"⚠️ push_service.dispatch_incident failed: {e}")

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

        # 3. Create a formal incident record for fall/seizure alerts.
        incident = await self._create_incident_from_alert(
            db=db,
            rule=rule,
            instance_id=instance_id,
            session_id=session_id,
            detection_result=result,
        )
        if incident is not None:
            await db.flush()
            log.extra_data = {
                **(log.extra_data or {}),
                "incident_id": incident.id,
            }
            # Queue payload for post-commit Redis publish (FR9 real-time alerting).
            self._pending_incident_publishes.append({
                "id": incident.id,
                "event_type": incident.event_type,
                "severity": incident.severity,
                "status": incident.status,
                "patient_id": incident.patient_id,
                "camera_config_id": incident.camera_config_id,
                "pipeline_instance_id": incident.pipeline_instance_id,
                "session_id": incident.session_id,
                "confidence": float(incident.confidence) if incident.confidence is not None else None,
                "threshold": float(incident.threshold) if incident.threshold is not None else None,
                "detected_at": (incident.detected_at.isoformat()
                                if incident.detected_at else datetime.now(timezone.utc).isoformat()),
            })

        print(f"🔔 ALERT: {message}")

        # 4. Actions (e.g. Webhooks/mobile push) can extend from this hook.

    async def _create_incident_from_alert(
        self,
        db: AsyncSession,
        rule: AlertRule,
        instance_id: Optional[int],
        session_id: int,
        detection_result: Any,
    ) -> Incident | None:
        model_name = (rule.model_name or "").lower()
        if model_name not in {"fall_detection", "seizure_detection"}:
            return None

        event_type = "fall" if model_name == "fall_detection" else "seizure"
        detection_payload = (
            detection_result
            if isinstance(detection_result, dict)
            else {"value": detection_result}
        )

        confidence_raw = detection_payload.get("probability") or detection_payload.get("confidence")
        try:
            confidence = float(confidence_raw) if confidence_raw is not None else None
        except (TypeError, ValueError):
            confidence = None

        trigger_condition = rule.trigger_condition or {}
        threshold_raw = trigger_condition.get("confidence_min")
        try:
            threshold = float(threshold_raw) if threshold_raw is not None else None
        except (TypeError, ValueError):
            threshold = None

        camera_config_id = None
        patient_id = None
        if instance_id is not None:
            instance_result = await db.execute(
                select(PipelineInstance).where(PipelineInstance.id == instance_id)
            )
            instance = instance_result.scalar_one_or_none()
            if instance is not None:
                camera_config_id = instance.camera_config_id

        if camera_config_id is not None:
            camera_result = await db.execute(
                select(CameraConfig).where(CameraConfig.id == camera_config_id)
            )
            camera = camera_result.scalar_one_or_none()
            if camera is not None:
                patient_id = camera.patient_id

        incident = Incident(
            event_type=event_type,
            status="new",
            severity="critical" if event_type == "fall" else "warning",
            camera_config_id=camera_config_id,
            patient_id=patient_id,
            pipeline_instance_id=instance_id,
            session_id=session_id,
            confidence=confidence,
            threshold=threshold,
            details={
                "rule_id": rule.id,
                "rule_name": rule.name,
                "model_name": rule.model_name,
                "trigger_condition": trigger_condition,
                "detection_data": detection_payload,
            },
        )
        db.add(incident)
        return incident

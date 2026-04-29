"""
Activity Logging Service

Centralized logging service for all system events, errors, and activities.
Logs events to the database and provides querying capabilities.
"""

from datetime import datetime, timezone, timedelta
from typing import Optional
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, and_, or_
from sqlalchemy.sql.elements import BinaryExpression

from app.database import get_db
from app.models import ActivityLog
from app.schemas import ActivityLogCreate, ActivityLogFilter, ActivityLogResponse


class ActivityLogger:
    """
    Centralized activity logging service.

    Provides methods to log various events and query logs.
    """

    def __init__(self, db_session: Optional[AsyncSession] = None):
        self.db_session = db_session

    async def log(
        self,
        event_type: str,
        message: str,
        source: str = "backend",
        severity: str = "info",
        pipeline_instance_id: Optional[int] = None,
        session_id: Optional[int] = None,
        extra_data: Optional[dict] = None,
        db: Optional[AsyncSession] = None,
    ) -> ActivityLog:
        """
        Log an activity event.

        Args:
            event_type: Type of event (e.g., 'pipeline_start', 'error', 'api_call')
            message: Human-readable message
            source: Source component ('backend', 'ml_manager', 'frontend')
            severity: Log level ('debug', 'info', 'warning', 'error', 'critical')
            pipeline_instance_id: Related pipeline instance ID
            session_id: Related session ID
            extra_data: Additional metadata as dict
            db: Database session (will use self.db_session if not provided)

        Returns:
            Created ActivityLog instance
        """
        db = db or self.db_session
        if not db:
            raise ValueError("No database session available")

        log_entry = ActivityLog(
            event_type=event_type,
            source=source,
            severity=severity,
            message=message,
            pipeline_instance_id=pipeline_instance_id,
            session_id=session_id,
            extra_data=extra_data or {},
        )

        db.add(log_entry)
        await db.commit()
        await db.refresh(log_entry)

        return log_entry

    async def log_info(self, event_type: str, message: str, **kwargs) -> ActivityLog:
        """Log an info-level event."""
        return await self.log(event_type, message, severity="info", **kwargs)

    async def log_warning(self, event_type: str, message: str, **kwargs) -> ActivityLog:
        """Log a warning-level event."""
        return await self.log(event_type, message, severity="warning", **kwargs)

    async def log_error(self, event_type: str, message: str, **kwargs) -> ActivityLog:
        """Log an error-level event."""
        return await self.log(event_type, message, severity="error", **kwargs)

    async def log_critical(self, event_type: str, message: str, **kwargs) -> ActivityLog:
        """Log a critical-level event."""
        return await self.log(event_type, message, severity="critical", **kwargs)

    async def log_api_call(
        self,
        method: str,
        endpoint: str,
        status_code: int,
        user_info: Optional[dict] = None,
        response_time_ms: Optional[float] = None,
        db: Optional[AsyncSession] = None,
    ) -> ActivityLog:
        """
        Log an API call event.

        Args:
            method: HTTP method (GET, POST, etc.)
            endpoint: API endpoint path
            status_code: HTTP response status code
            user_info: User/client information
            response_time_ms: Response time in milliseconds
            db: Database session
        """
        severity = "error" if status_code >= 400 else "info"
        extra_data = {
            "method": method,
            "endpoint": endpoint,
            "status_code": status_code,
            "user_info": user_info or {},
        }
        if response_time_ms is not None:
            extra_data["response_time_ms"] = response_time_ms

        return await self.log(
            event_type="api_call",
            message=f"{method} {endpoint} -> {status_code}",
            severity=severity,
            extra_data=extra_data,
            db=db,
        )

    async def log_pipeline_event(
        self,
        event_type: str,
        pipeline_instance_id: int,
        message: str,
        severity: str = "info",
        extra_data: Optional[dict] = None,
        db: Optional[AsyncSession] = None,
    ) -> ActivityLog:
        """Log a pipeline-related event."""
        return await self.log(
            event_type=event_type,
            message=message,
            source="ml_manager",
            severity=severity,
            pipeline_instance_id=pipeline_instance_id,
            extra_data=extra_data,
            db=db,
        )

    async def log_instance_created(
        self,
        instance_id: int,
        instance_name: str,
        camera_config_id: int,
        enabled_models: list[str],
        db: Optional[AsyncSession] = None,
    ) -> ActivityLog:
        """Log pipeline instance creation."""
        return await self.log_pipeline_event(
            event_type="instance_created",
            pipeline_instance_id=instance_id,
            message=f"Pipeline instance '{instance_name}' created",
            extra_data={
                "instance_name": instance_name,
                "camera_config_id": camera_config_id,
                "enabled_models": enabled_models,
            },
            db=db,
        )

    async def log_instance_started(
        self,
        instance_id: int,
        camera_source: str,
        db: Optional[AsyncSession] = None,
    ) -> ActivityLog:
        """Log pipeline instance start."""
        return await self.log_pipeline_event(
            event_type="instance_started",
            pipeline_instance_id=instance_id,
            message=f"Pipeline instance {instance_id} started processing",
            extra_data={"camera_source": camera_source},
            db=db,
        )

    async def log_instance_stopped(
        self,
        instance_id: int,
        frames_processed: int,
        reason: str = "manual",
        db: Optional[AsyncSession] = None,
    ) -> ActivityLog:
        """Log pipeline instance stop."""
        return await self.log_pipeline_event(
            event_type="instance_stopped",
            pipeline_instance_id=instance_id,
            message=f"Pipeline instance {instance_id} stopped ({frames_processed} frames)",
            extra_data={
                "frames_processed": frames_processed,
                "reason": reason,
            },
            db=db,
        )

    async def log_model_config_updated(
        self,
        instance_id: int,
        model_name: str,
        old_config: dict,
        new_config: dict,
        db: Optional[AsyncSession] = None,
    ) -> ActivityLog:
        """Log model configuration update."""
        return await self.log_pipeline_event(
            event_type="model_config_updated",
            pipeline_instance_id=instance_id,
            message=f"Model '{model_name}' config updated for instance {instance_id}",
            extra_data={
                "model_name": model_name,
                "old_config": old_config,
                "new_config": new_config,
            },
            db=db,
        )

    async def query_logs(
        self,
        filters: ActivityLogFilter,
        db: Optional[AsyncSession] = None,
    ) -> tuple[list[ActivityLog], int]:
        """
        Query activity logs with filtering and pagination.

        Args:
            filters: Filter parameters
            db: Database session

        Returns:
            Tuple of (log_entries, total_count)
        """
        db = db or self.db_session
        if not db:
            raise ValueError("No database session available")

        # Build base query
        query = select(ActivityLog)

        # Apply filters
        conditions = []

        if filters.event_type:
            conditions.append(ActivityLog.event_type == filters.event_type)

        if filters.severity:
            conditions.append(ActivityLog.severity == filters.severity)

        if filters.pipeline_instance_id:
            conditions.append(ActivityLog.pipeline_instance_id == filters.pipeline_instance_id)

        if filters.session_id:
            conditions.append(ActivityLog.session_id == filters.session_id)

        if filters.start_time:
            conditions.append(ActivityLog.created_at >= filters.start_time)

        if filters.end_time:
            conditions.append(ActivityLog.created_at <= filters.end_time)

        # Apply conditions
        if conditions:
            query = query.where(and_(*conditions))

        # Get total count
        count_query = select(func.count(ActivityLog.id))
        if conditions:
            count_query = count_query.where(and_(*conditions))

        result = await db.execute(count_query)
        total_count = result.scalar()

        # Apply ordering and pagination
        query = query.order_by(ActivityLog.created_at.desc())
        query = query.offset(filters.offset).limit(filters.limit)

        # Execute query
        result = await db.execute(query)
        logs = result.scalars().all()

        return list(logs), total_count

    async def get_recent_errors(
        self,
        hours: int = 24,
        limit: int = 50,
        db: Optional[AsyncSession] = None,
    ) -> list[ActivityLog]:
        """Get recent error and critical logs."""
        since = datetime.now(timezone.utc) - timedelta(hours=hours)

        filters = ActivityLogFilter(
            severity="error",
            start_time=since,
            limit=limit,
        )

        # Also get critical logs
        critical_filters = ActivityLogFilter(
            severity="critical",
            start_time=since,
            limit=limit,
        )

        error_logs, _ = await self.query_logs(filters, db)
        critical_logs, _ = await self.query_logs(critical_filters, db)

        # Combine and sort by time
        all_logs = error_logs + critical_logs
        all_logs.sort(key=lambda x: x.created_at, reverse=True)

        return all_logs[:limit]

    async def get_pipeline_activity(
        self,
        instance_id: int,
        hours: int = 24,
        db: Optional[AsyncSession] = None,
    ) -> list[ActivityLog]:
        """Get recent activity for a specific pipeline instance."""
        since = datetime.now(timezone.utc) - timedelta(hours=hours)

        filters = ActivityLogFilter(
            pipeline_instance_id=instance_id,
            start_time=since,
            limit=100,
        )

        logs, _ = await self.query_logs(filters, db)
        return logs


# Singleton logger instance
_logger: Optional[ActivityLogger] = None


def get_logger() -> ActivityLogger:
    """Get the activity logger singleton."""
    global _logger
    if _logger is None:
        _logger = ActivityLogger()
    return _logger


async def log_event(
    event_type: str,
    message: str,
    severity: str = "info",
    source: str = "backend",
    pipeline_instance_id: Optional[int] = None,
    session_id: Optional[int] = None,
    extra_data: Optional[dict] = None,
) -> ActivityLog:
    """
    Convenience function to log an event.

    Uses a new database session for the operation.
    """
    from app.database import get_db

    async for db in get_db():
        logger = ActivityLogger(db)
        return await logger.log(
            event_type=event_type,
            message=message,
            severity=severity,
            source=source,
            pipeline_instance_id=pipeline_instance_id,
            session_id=session_id,
            extra_data=extra_data,
            db=db,
        )
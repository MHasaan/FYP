"""
Activity Log API Routes

Endpoints for querying and managing activity logs.
"""

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List, Optional
from datetime import datetime, timedelta, timezone

from app.database import get_db
from app.schemas import (
    ActivityLogResponse,
    ActivityLogFilter,
    PaginatedResponse,
)
from app.services.activity_logger import ActivityLogger


router = APIRouter(prefix="/api/logs", tags=["Activity Logs"])


@router.get("/", response_model=PaginatedResponse)
async def get_activity_logs(
    event_type: Optional[str] = Query(None, description="Filter by event type"),
    severity: Optional[str] = Query(None, description="Filter by severity level"),
    pipeline_instance_id: Optional[int] = Query(None, description="Filter by pipeline instance"),
    session_id: Optional[int] = Query(None, description="Filter by session"),
    start_time: Optional[datetime] = Query(None, description="Start time filter (ISO format)"),
    end_time: Optional[datetime] = Query(None, description="End time filter (ISO format)"),
    limit: int = Query(50, ge=1, le=1000, description="Number of logs to return"),
    offset: int = Query(0, ge=0, description="Number of logs to skip"),
    db: AsyncSession = Depends(get_db),
):
    """
    Get activity logs with filtering and pagination.

    Supports filtering by event type, severity, pipeline instance, session,
    and time range. Results are ordered by creation time (newest first).
    """
    logger = ActivityLogger(db)

    filters = ActivityLogFilter(
        event_type=event_type,
        severity=severity,
        pipeline_instance_id=pipeline_instance_id,
        session_id=session_id,
        start_time=start_time,
        end_time=end_time,
        limit=limit,
        offset=offset,
    )

    logs, total_count = await logger.query_logs(filters)

    return PaginatedResponse(
        items=[ActivityLogResponse.model_validate(log) for log in logs],
        total=total_count,
        limit=limit,
        offset=offset,
        has_more=(offset + len(logs)) < total_count,
    )


@router.get("/recent-errors", response_model=List[ActivityLogResponse])
async def get_recent_errors(
    hours: int = Query(24, ge=1, le=168, description="Hours to look back"),
    limit: int = Query(50, ge=1, le=200, description="Max number of errors to return"),
    db: AsyncSession = Depends(get_db),
):
    """
    Get recent error and critical level logs.

    Returns errors and critical events from the specified time period.
    """
    logger = ActivityLogger(db)
    error_logs = await logger.get_recent_errors(hours=hours, limit=limit)

    return [ActivityLogResponse.model_validate(log) for log in error_logs]


@router.get("/pipeline/{instance_id}", response_model=List[ActivityLogResponse])
async def get_pipeline_activity(
    instance_id: int,
    hours: int = Query(24, ge=1, le=168, description="Hours to look back"),
    db: AsyncSession = Depends(get_db),
):
    """
    Get recent activity for a specific pipeline instance.

    Returns all events related to the specified pipeline instance.
    """
    logger = ActivityLogger(db)
    logs = await logger.get_pipeline_activity(instance_id, hours=hours)

    return [ActivityLogResponse.model_validate(log) for log in logs]


@router.get("/statistics")
async def get_log_statistics(
    hours: int = Query(24, ge=1, le=168, description="Hours to analyze"),
    db: AsyncSession = Depends(get_db),
):
    """
    Get activity log statistics for the specified time period.

    Returns counts by event type, severity, and source.
    """
    since = datetime.now(timezone.utc) - timedelta(hours=hours)

    logger = ActivityLogger(db)

    # Get all logs in the time period
    filters = ActivityLogFilter(
        start_time=since,
        limit=10000,  # High limit to get all
    )

    logs, total_count = await logger.query_logs(filters)

    # Calculate statistics
    stats = {
        "total_logs": total_count,
        "time_period_hours": hours,
        "by_severity": {},
        "by_event_type": {},
        "by_source": {},
        "timeline": {},  # Hour-by-hour breakdown
    }

    # Count by categories
    for log in logs:
        # Severity stats
        severity = log.severity
        stats["by_severity"][severity] = stats["by_severity"].get(severity, 0) + 1

        # Event type stats
        event_type = log.event_type
        stats["by_event_type"][event_type] = stats["by_event_type"].get(event_type, 0) + 1

        # Source stats
        source = log.source
        stats["by_source"][source] = stats["by_source"].get(source, 0) + 1

        # Timeline stats (by hour)
        hour_key = log.created_at.strftime("%Y-%m-%d %H:00")
        stats["timeline"][hour_key] = stats["timeline"].get(hour_key, 0) + 1

    return stats


@router.get("/event-types")
async def get_event_types(db: AsyncSession = Depends(get_db)):
    """
    Get list of all event types in the system.

    Returns unique event types found in the activity logs.
    """
    from sqlalchemy import select, distinct
    from app.models import ActivityLog

    query = select(distinct(ActivityLog.event_type)).order_by(ActivityLog.event_type)
    result = await db.execute(query)
    event_types = result.scalars().all()

    return {
        "event_types": list(event_types),
        "count": len(event_types),
    }


@router.delete("/cleanup")
async def cleanup_old_logs(
    days: int = Query(30, ge=1, le=365, description="Delete logs older than this many days"),
    db: AsyncSession = Depends(get_db),
):
    """
    Delete activity logs older than the specified number of days.

    This endpoint helps manage database size by cleaning up old log entries.
    """
    from sqlalchemy import delete
    from app.models import ActivityLog

    cutoff_date = datetime.now(timezone.utc) - timedelta(days=days)

    # Count logs to be deleted
    from sqlalchemy import select, func
    count_query = select(func.count(ActivityLog.id)).where(
        ActivityLog.created_at < cutoff_date
    )
    result = await db.execute(count_query)
    count_to_delete = result.scalar()

    if count_to_delete == 0:
        return {
            "message": "No logs found older than specified date",
            "deleted_count": 0,
            "cutoff_date": cutoff_date.isoformat(),
        }

    # Delete old logs
    delete_query = delete(ActivityLog).where(ActivityLog.created_at < cutoff_date)
    await db.execute(delete_query)
    await db.commit()

    return {
        "message": f"Successfully deleted {count_to_delete} old log entries",
        "deleted_count": count_to_delete,
        "cutoff_date": cutoff_date.isoformat(),
    }
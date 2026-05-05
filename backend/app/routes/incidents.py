"""
Incident creation, filtering, acknowledgement, and resolution routes.
"""

from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models import Incident, PatientProfile, UserAccount
from app.schemas import IncidentCreate, IncidentResponse, IncidentUpdate, PaginatedResponse
from app.services.auth_service import get_current_user, require_roles


router = APIRouter(prefix="/api/incidents", tags=["Incidents"])


def _incident_scope(user: UserAccount):
    query = select(Incident)
    count_query = select(func.count(Incident.id))
    if user.role == "admin":
        return query, count_query

    query = query.outerjoin(PatientProfile, Incident.patient_id == PatientProfile.id)
    count_query = count_query.outerjoin(PatientProfile, Incident.patient_id == PatientProfile.id)
    scope_filter = (
        PatientProfile.caregiver_id == user.id
        if user.role == "caregiver"
        else or_(
            PatientProfile.relative_user_id == user.id,
            PatientProfile.primary_contact_email == user.email,
        )
    )
    return query.where(scope_filter), count_query.where(scope_filter)


def _apply_filters(
    query,
    patient_id: Optional[int],
    camera_config_id: Optional[int],
    status_filter: Optional[str],
    event_type: Optional[str],
    start_time: Optional[datetime],
    end_time: Optional[datetime],
):
    if patient_id is not None:
        query = query.where(Incident.patient_id == patient_id)
    if camera_config_id is not None:
        query = query.where(Incident.camera_config_id == camera_config_id)
    if status_filter:
        query = query.where(Incident.status == status_filter)
    if event_type:
        query = query.where(Incident.event_type == event_type)
    if start_time:
        query = query.where(Incident.detected_at >= start_time)
    if end_time:
        query = query.where(Incident.detected_at <= end_time)
    return query


async def _get_scoped_incident(incident_id: int, user: UserAccount, db: AsyncSession) -> Incident:
    query, _ = _incident_scope(user)
    result = await db.execute(query.where(Incident.id == incident_id))
    incident = result.scalar_one_or_none()
    if incident is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Incident not found")
    return incident


@router.get("/", response_model=PaginatedResponse)
async def list_incidents(
    patient_id: Optional[int] = Query(None),
    camera_config_id: Optional[int] = Query(None),
    status_filter: Optional[str] = Query(None, alias="status"),
    event_type: Optional[str] = Query(None),
    start_time: Optional[datetime] = Query(None),
    end_time: Optional[datetime] = Query(None),
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
    user: UserAccount = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """List incidents with patient/date/status filters."""
    query, count_query = _incident_scope(user)
    query = _apply_filters(query, patient_id, camera_config_id, status_filter, event_type, start_time, end_time)
    count_query = _apply_filters(count_query, patient_id, camera_config_id, status_filter, event_type, start_time, end_time)

    total_result = await db.execute(count_query)
    total = total_result.scalar_one() or 0

    rows = await db.execute(
        query.order_by(Incident.detected_at.desc(), Incident.id.desc()).limit(limit).offset(offset)
    )
    incidents = rows.scalars().all()
    return PaginatedResponse(
        items=[IncidentResponse.model_validate(incident) for incident in incidents],
        total=total,
        limit=limit,
        offset=offset,
        has_more=(offset + len(incidents)) < total,
    )


@router.post("/", response_model=IncidentResponse, status_code=status.HTTP_201_CREATED)
async def create_incident(
    payload: IncidentCreate,
    _: UserAccount = Depends(require_roles("admin", "caregiver")),
    db: AsyncSession = Depends(get_db),
):
    """Create a manual or externally detected incident."""
    data = payload.model_dump(exclude_unset=True)
    incident = Incident(**data)
    db.add(incident)
    await db.commit()
    await db.refresh(incident)
    return incident


@router.get("/{incident_id}", response_model=IncidentResponse)
async def get_incident(
    incident_id: int,
    user: UserAccount = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Open one incident detail record."""
    return await _get_scoped_incident(incident_id, user, db)


@router.patch("/{incident_id}", response_model=IncidentResponse)
async def update_incident(
    incident_id: int,
    payload: IncidentUpdate,
    user: UserAccount = Depends(require_roles("admin", "caregiver")),
    db: AsyncSession = Depends(get_db),
):
    """Update incident status, notes, or review metadata."""
    incident = await _get_scoped_incident(incident_id, user, db)
    updates = payload.model_dump(exclude_unset=True)
    status_value = updates.get("status")
    now = datetime.now(timezone.utc)

    for key, value in updates.items():
        setattr(incident, key, value)

    if status_value == "acknowledged" and incident.acknowledged_at is None:
        incident.acknowledged_at = now
    if status_value == "resolved":
        if incident.acknowledged_at is None:
            incident.acknowledged_at = now
        incident.resolved_at = now

    await db.commit()
    await db.refresh(incident)
    return incident


@router.post("/{incident_id}/acknowledge", response_model=IncidentResponse)
async def acknowledge_incident(
    incident_id: int,
    user: UserAccount = Depends(require_roles("admin", "caregiver")),
    db: AsyncSession = Depends(get_db),
):
    """Mark an incident acknowledged."""
    incident = await _get_scoped_incident(incident_id, user, db)
    incident.status = "acknowledged"
    incident.acknowledged_at = incident.acknowledged_at or datetime.now(timezone.utc)
    await db.commit()
    await db.refresh(incident)
    return incident


@router.post("/{incident_id}/resolve", response_model=IncidentResponse)
async def resolve_incident(
    incident_id: int,
    user: UserAccount = Depends(require_roles("admin", "caregiver")),
    db: AsyncSession = Depends(get_db),
):
    """Mark an incident resolved."""
    now = datetime.now(timezone.utc)
    incident = await _get_scoped_incident(incident_id, user, db)
    incident.status = "resolved"
    incident.acknowledged_at = incident.acknowledged_at or now
    incident.resolved_at = now
    await db.commit()
    await db.refresh(incident)
    return incident

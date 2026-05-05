"""
Basic reporting routes for incident history.
"""

from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, Query
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models import Incident, PatientProfile, UserAccount
from app.schemas import IncidentReportResponse, IncidentResponse
from app.services.auth_service import get_current_user


router = APIRouter(prefix="/api/reports", tags=["Reports"])


def _scoped_incident_report_query(user: UserAccount):
    query = select(Incident)
    if user.role == "admin":
        return query
    query = query.outerjoin(PatientProfile, Incident.patient_id == PatientProfile.id)
    if user.role == "caregiver":
        return query.where(PatientProfile.caregiver_id == user.id)
    return query.where(
        or_(
            PatientProfile.relative_user_id == user.id,
            PatientProfile.primary_contact_email == user.email,
        )
    )


@router.get("/incidents", response_model=IncidentReportResponse)
async def incident_report(
    patient_id: Optional[int] = Query(None),
    camera_config_id: Optional[int] = Query(None),
    start_time: Optional[datetime] = Query(None),
    end_time: Optional[datetime] = Query(None),
    user: UserAccount = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Summarize incident history by patient/camera/time period."""
    query = _scoped_incident_report_query(user)
    if patient_id is not None:
        query = query.where(Incident.patient_id == patient_id)
    if camera_config_id is not None:
        query = query.where(Incident.camera_config_id == camera_config_id)
    if start_time is not None:
        query = query.where(Incident.detected_at >= start_time)
    if end_time is not None:
        query = query.where(Incident.detected_at <= end_time)

    result = await db.execute(query.order_by(Incident.detected_at.desc()))
    incidents = result.scalars().all()

    by_event_type: dict[str, int] = {}
    by_status: dict[str, int] = {}
    by_severity: dict[str, int] = {}
    for incident in incidents:
        by_event_type[incident.event_type] = by_event_type.get(incident.event_type, 0) + 1
        by_status[incident.status] = by_status.get(incident.status, 0) + 1
        by_severity[incident.severity] = by_severity.get(incident.severity, 0) + 1

    return IncidentReportResponse(
        total=len(incidents),
        by_event_type=by_event_type,
        by_status=by_status,
        by_severity=by_severity,
        patient_id=patient_id,
        camera_config_id=camera_config_id,
        start_time=start_time,
        end_time=end_time,
        recent=[IncidentResponse.model_validate(row) for row in incidents[:10]],
    )

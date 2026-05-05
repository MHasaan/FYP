"""
System capability and roadmap routes.
"""

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models import SystemPlan
from app.schemas import SystemPlanResponse


router = APIRouter(prefix="/api/system", tags=["System"])


@router.get("/capabilities")
async def get_system_capabilities(db: AsyncSession = Depends(get_db)):
    """Return implemented and placeholder Eldercare capabilities."""
    result = await db.execute(select(SystemPlan).order_by(SystemPlan.key.asc()))
    plans = result.scalars().all()

    return {
        "functional_requirements": {
            "FR1": "User registration/login with admin, caregiver, and patient/relative roles",
            "FR2": "Camera CRUD with name, location, group, and patient linking",
            "FR3": "Patient profile management with risk and contact attributes",
            "FR4": "Live and multi-camera monitoring through frontend WebSockets",
            "FR5": "Continuous pose extraction pipeline for incoming frames",
            "FR6": "Fall detection model support and alert-to-incident creation",
            "FR7": "Seizure detection pipeline placeholder using VSViG/WU-SAHZU-EMU naming",
            "FR8": "Incident record creation for fall/seizure detections",
            "FR9": "Frontend incident refresh plus push-notification placeholder",
            "FR10": "Incident review, acknowledgement, and resolution",
            "FR11": "Detector thresholds and enable/disable settings per camera/patient",
            "FR12": "Basic incident history reports by patient/camera/time period",
            "FR13": "Mobile application support planned through device tokens",
            "FR14": "Local database/offline mode planned as a future system plan",
        },
        "models": {
            "pose": {"status": "implemented", "keypoints": 18},
            "fall_detection": {"status": "implemented", "features": ["pose", "local_patches", "global_patches", "kinematics"]},
            "seizure_detection": {
                "status": "placeholder",
                "model": "VSViG",
                "dataset": "WU-SAHZU-EMU",
                "note": "Pipeline contract is exposed; trained weights/inference integration can be added later.",
            },
        },
        "role_access": {
            "admin": {
                "screens": ["Overview", "Monitor", "Live", "Admin", "Insights"],
                "permissions": [
                    "manage_users",
                    "manage_patients",
                    "manage_cameras",
                    "manage_detection_settings",
                    "manage_alert_rules",
                    "manage_schedules",
                    "acknowledge_resolve_incidents",
                    "view_reports",
                ],
            },
            "caregiver": {
                "screens": ["Overview", "Monitor", "Live", "Admin", "Insights"],
                "permissions": [
                    "manage_assigned_patients",
                    "manage_assigned_cameras",
                    "manage_detection_settings",
                    "acknowledge_resolve_incidents",
                    "view_reports",
                ],
            },
            "patient_relative": {
                "screens": ["Overview", "Live", "Admin (Account)", "Insights"],
                "permissions": [
                    "view_assigned_incidents",
                    "view_incident_history",
                    "view_live_monitoring",
                ],
            },
        },
        "plans": [SystemPlanResponse.model_validate(plan) for plan in plans],
    }

"""
Patient profile management routes.
"""

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models import PatientProfile, UserAccount
from app.schemas import PatientCreate, PatientResponse, PatientUpdate
from app.services.auth_service import get_current_user, require_roles


router = APIRouter(prefix="/api/patients", tags=["Patients"])


def _scoped_patient_query(user: UserAccount):
    query = select(PatientProfile)
    if user.role == "admin":
        return query
    if user.role == "caregiver":
        return query.where(PatientProfile.caregiver_id == user.id)
    return query.where(
        or_(
            PatientProfile.relative_user_id == user.id,
            PatientProfile.primary_contact_email == user.email,
        )
    )


async def _get_scoped_patient(patient_id: int, user: UserAccount, db: AsyncSession) -> PatientProfile:
    result = await db.execute(_scoped_patient_query(user).where(PatientProfile.id == patient_id))
    patient = result.scalar_one_or_none()
    if patient is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Patient not found")
    return patient


@router.get("/", response_model=list[PatientResponse])
async def list_patients(
    search: str | None = Query(None),
    user: UserAccount = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """List patient profiles visible to the current user's role."""
    query = _scoped_patient_query(user)
    if search:
        query = query.where(PatientProfile.full_name.ilike(f"%{search.strip()}%"))
    result = await db.execute(query.order_by(PatientProfile.created_at.desc()))
    return result.scalars().all()


@router.post("/", response_model=PatientResponse, status_code=status.HTTP_201_CREATED)
async def create_patient(
    payload: PatientCreate,
    user: UserAccount = Depends(require_roles("admin", "caregiver")),
    db: AsyncSession = Depends(get_db),
):
    """Create a patient profile with risk and contact details.

    Only admins can assign caregiver_id / relative_user_id — caregivers are
    auto-assigned to themselves and can't pin patients to other caregivers or
    relatives, which would otherwise be a privilege-escalation path matching
    the same restriction we apply in update_patient.
    """
    data = payload.model_dump()
    if user.role == "caregiver":
        # Force caregiver_id to self; ignore any client-supplied value.
        data["caregiver_id"] = user.id
        # Caregivers may not assign relatives at all — admin-only field.
        data.pop("relative_user_id", None)

    patient = PatientProfile(**data)
    db.add(patient)
    await db.commit()
    await db.refresh(patient)
    return patient


@router.get("/{patient_id}", response_model=PatientResponse)
async def get_patient(
    patient_id: int,
    user: UserAccount = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get one role-scoped patient profile."""
    return await _get_scoped_patient(patient_id, user, db)


@router.patch("/{patient_id}", response_model=PatientResponse)
async def update_patient(
    patient_id: int,
    payload: PatientUpdate,
    user: UserAccount = Depends(require_roles("admin", "caregiver")),
    db: AsyncSession = Depends(get_db),
):
    """Update demographic, risk, and contact fields."""
    patient = await _get_scoped_patient(patient_id, user, db)
    updates = payload.model_dump(exclude_unset=True)

    if user.role == "caregiver":
        updates.pop("caregiver_id", None)
        updates.pop("relative_user_id", None)

    for key, value in updates.items():
        setattr(patient, key, value)

    await db.commit()
    await db.refresh(patient)
    return patient


@router.delete("/{patient_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_patient(
    patient_id: int,
    user: UserAccount = Depends(require_roles("admin", "caregiver")),
    db: AsyncSession = Depends(get_db),
):
    """Delete a patient profile."""
    patient = await _get_scoped_patient(patient_id, user, db)
    await db.delete(patient)
    await db.commit()

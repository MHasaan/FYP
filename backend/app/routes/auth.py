"""
Authentication and user-role routes.
"""

from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models import AuthToken, UserAccount
from app.schemas import (
    AuthTokenResponse,
    PasswordChange,
    UserCreate,
    UserLogin,
    UserRegister,
    UserResponse,
    UserUpdate,
)
from app.services.auth_service import (
    create_access_token,
    get_current_user,
    hash_password,
    hash_token,
    require_roles,
    verify_password,
)


router = APIRouter(prefix="/api/auth", tags=["Auth"])


def _normalize_email(email: str) -> str:
    return email.strip().lower()


async def _email_exists(db: AsyncSession, email: str) -> bool:
    result = await db.execute(select(UserAccount.id).where(UserAccount.email == email))
    return result.scalar_one_or_none() is not None


async def _issue_token(db: AsyncSession, user: UserAccount) -> AuthTokenResponse:
    raw_token, token_digest, expires_at = create_access_token()
    db_token = AuthToken(
        user_id=user.id,
        token_hash=token_digest,
        expires_at=expires_at,
    )
    db.add(db_token)
    await db.commit()
    await db.refresh(user)
    return AuthTokenResponse(
        access_token=raw_token,
        expires_at=expires_at,
        user=UserResponse.model_validate(user),
    )


@router.post("/register", response_model=AuthTokenResponse, status_code=status.HTTP_201_CREATED)
async def register(payload: UserRegister, db: AsyncSession = Depends(get_db)):
    """Register a caregiver or patient/relative user and sign them in."""
    email = _normalize_email(payload.email)
    if await _email_exists(db, email):
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Email already registered")

    total_result = await db.execute(select(func.count(UserAccount.id)))
    has_users = (total_result.scalar_one() or 0) > 0
    if has_users and payload.role == "admin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin users must be created by an existing administrator",
        )

    user = UserAccount(
        full_name=payload.full_name.strip(),
        email=email,
        password_hash=hash_password(payload.password),
        role=payload.role,
        phone=payload.phone,
        is_active=True,
    )
    db.add(user)
    await db.commit()
    await db.refresh(user)
    return await _issue_token(db, user)


@router.post("/login", response_model=AuthTokenResponse)
async def login(payload: UserLogin, db: AsyncSession = Depends(get_db)):
    """Sign in with email/password and receive a bearer token."""
    email = _normalize_email(payload.email)
    result = await db.execute(select(UserAccount).where(UserAccount.email == email))
    user = result.scalar_one_or_none()
    if user is None or not user.is_active or not verify_password(payload.password, user.password_hash):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid email or password")
    return await _issue_token(db, user)


@router.get("/me", response_model=UserResponse)
async def me(user: UserAccount = Depends(get_current_user)):
    """Return the current signed-in user."""
    return user


@router.patch("/me", response_model=UserResponse)
async def update_me(
    payload: UserUpdate,
    user: UserAccount = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Update the current user's own profile.

    Users can edit `full_name` and `phone`. Privileged fields (`role`,
    `is_active`, `password`) are stripped — those require admin (`PATCH
    /users/{id}`) or the dedicated `/me/password` route.
    """
    updates = payload.model_dump(exclude_unset=True)
    # Don't let users escalate themselves via this endpoint.
    for forbidden in ("role", "is_active", "password"):
        updates.pop(forbidden, None)

    for key, value in updates.items():
        setattr(user, key, value)
    await db.commit()
    await db.refresh(user)
    return user


@router.post("/logout")
async def logout(
    payload: dict,
    db: AsyncSession = Depends(get_db),
):
    """Revoke the current token.

    Intentionally does NOT require `get_current_user` — a client should be able
    to log out cleanly even after its token has expired. We look up the token
    directly and revoke if it exists and isn't already revoked. Always returns
    200 so the client UX is the same regardless of token validity.
    """
    raw_token = payload.get("access_token") if isinstance(payload, dict) else None
    if not raw_token:
        return {"status": "ok"}

    result = await db.execute(
        select(AuthToken).where(
            AuthToken.token_hash == hash_token(raw_token),
            AuthToken.revoked_at.is_(None),
        )
    )
    token = result.scalar_one_or_none()
    if token:
        token.revoked_at = datetime.now(timezone.utc)
        await db.commit()
    return {"status": "ok"}


@router.get("/users-count")
async def users_count(db: AsyncSession = Depends(get_db)):
    """Public: total user count. Used by the LoginScreen to gate first-admin signup."""
    result = await db.execute(select(func.count(UserAccount.id)))
    return {"count": result.scalar_one() or 0}


@router.post("/me/password")
async def change_password(
    payload: PasswordChange,
    user: UserAccount = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Allow the current user to change their own password."""
    if not verify_password(payload.current_password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Current password is incorrect",
        )
    user.password_hash = hash_password(payload.new_password)
    await db.commit()
    return {"status": "ok"}


@router.get("/users", response_model=list[UserResponse])
async def list_users(
    role: Optional[str] = None,
    _: UserAccount = Depends(require_roles("admin", "caregiver")),
    db: AsyncSession = Depends(get_db),
):
    """List users (admin/caregiver). Optional `role` filter for picker dropdowns."""
    query = select(UserAccount).where(UserAccount.is_active == True)  # noqa: E712
    if role:
        query = query.where(UserAccount.role == role)
    result = await db.execute(query.order_by(UserAccount.full_name))
    return result.scalars().all()


@router.post("/users", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
async def create_user(
    payload: UserCreate,
    _: UserAccount = Depends(require_roles("admin")),
    db: AsyncSession = Depends(get_db),
):
    """Create a role-specific user as an administrator."""
    email = _normalize_email(payload.email)
    if await _email_exists(db, email):
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Email already registered")

    user = UserAccount(
        full_name=payload.full_name.strip(),
        email=email,
        password_hash=hash_password(payload.password),
        role=payload.role,
        phone=payload.phone,
        is_active=payload.is_active,
    )
    db.add(user)
    await db.commit()
    await db.refresh(user)
    return user


@router.patch("/users/{user_id}", response_model=UserResponse)
async def update_user(
    user_id: int,
    payload: UserUpdate,
    _: UserAccount = Depends(require_roles("admin")),
    db: AsyncSession = Depends(get_db),
):
    """Update a user account and role."""
    result = await db.execute(select(UserAccount).where(UserAccount.id == user_id))
    user = result.scalar_one_or_none()
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

    updates = payload.model_dump(exclude_unset=True)
    password = updates.pop("password", None)
    for key, value in updates.items():
        setattr(user, key, value)
    if password:
        user.password_hash = hash_password(password)

    await db.commit()
    await db.refresh(user)
    return user


@router.delete("/users/{user_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_user(
    user_id: int,
    current_admin: UserAccount = Depends(require_roles("admin")),
    db: AsyncSession = Depends(get_db),
):
    """Deactivate a user account and revoke active tokens."""
    if current_admin.id == user_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Admins cannot delete their own account while signed in",
        )

    result = await db.execute(select(UserAccount).where(UserAccount.id == user_id))
    user = result.scalar_one_or_none()
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

    if user.role == "admin" and user.is_active:
        admin_count_result = await db.execute(
            select(func.count(UserAccount.id)).where(
                UserAccount.role == "admin",
                UserAccount.is_active == True,  # noqa: E712
            )
        )
        active_admin_count = admin_count_result.scalar_one() or 0
        if active_admin_count <= 1:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="At least one active admin account must remain",
            )

    now = datetime.now(timezone.utc)
    user.is_active = False
    user.updated_at = now

    token_result = await db.execute(
        select(AuthToken).where(
            AuthToken.user_id == user.id,
            AuthToken.revoked_at.is_(None),
        )
    )
    for token in token_result.scalars().all():
        token.revoked_at = now

    await db.commit()

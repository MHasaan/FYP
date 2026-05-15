"""
Authentication helpers for Eldercare users.
"""

import base64
import hashlib
import hmac
import secrets
from datetime import datetime, timedelta, timezone
from typing import Callable

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.database import get_db
from app.models import AuthToken, UserAccount


PASSWORD_ITERATIONS = 390_000
TOKEN_TTL_HOURS = 12
bearer_scheme = HTTPBearer(auto_error=False)


def hash_password(password: str) -> str:
    """Create a salted PBKDF2 password hash."""
    salt = secrets.token_bytes(16)
    digest = hashlib.pbkdf2_hmac(
        "sha256",
        password.encode("utf-8"),
        salt,
        PASSWORD_ITERATIONS,
    )
    return (
        f"pbkdf2_sha256${PASSWORD_ITERATIONS}$"
        f"{base64.b64encode(salt).decode()}$"
        f"{base64.b64encode(digest).decode()}"
    )


def verify_password(password: str, stored_hash: str) -> bool:
    """Verify a password against a PBKDF2 hash."""
    try:
        algorithm, iterations_text, salt_text, digest_text = stored_hash.split("$", 3)
        if algorithm != "pbkdf2_sha256":
            return False
        iterations = int(iterations_text)
        salt = base64.b64decode(salt_text.encode())
        expected = base64.b64decode(digest_text.encode())
        actual = hashlib.pbkdf2_hmac(
            "sha256",
            password.encode("utf-8"),
            salt,
            iterations,
        )
        return hmac.compare_digest(actual, expected)
    except Exception:
        return False


def hash_token(token: str) -> str:
    """Hash an opaque token before storing or looking it up."""
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def create_access_token() -> tuple[str, str, datetime]:
    """Return raw token, token hash, and expiry timestamp."""
    token = secrets.token_urlsafe(32)
    expires_at = datetime.now(timezone.utc) + timedelta(hours=TOKEN_TTL_HOURS)
    return token, hash_token(token), expires_at


async def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    db: AsyncSession = Depends(get_db),
) -> UserAccount:
    """Resolve the current user from the Authorization bearer token."""
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing bearer token",
        )

    token_digest = hash_token(credentials.credentials)
    now = datetime.now(timezone.utc)
    result = await db.execute(
        select(AuthToken)
        .options(selectinload(AuthToken.user))
        .join(AuthToken.user)
        .where(
            AuthToken.token_hash == token_digest,
            AuthToken.revoked_at.is_(None),
            AuthToken.expires_at > now,
            UserAccount.is_active == True,  # noqa: E712
        )
    )
    auth_token = result.scalar_one_or_none()
    if auth_token is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
        )
    return auth_token.user


def require_roles(*roles: str) -> Callable:
    """FastAPI dependency factory for role-specific access."""
    async def _dependency(user: UserAccount = Depends(get_current_user)) -> UserAccount:
        if user.role not in roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="This role is not allowed to access this feature",
            )
        return user

    return _dependency


async def get_user_from_token(token: str, db: AsyncSession) -> UserAccount | None:
    """Resolve a UserAccount from a raw token (for WebSocket auth via ?token= query)."""
    if not token:
        return None
    token_digest = hash_token(token)
    now = datetime.now(timezone.utc)
    result = await db.execute(
        select(AuthToken)
        .options(selectinload(AuthToken.user))
        .join(AuthToken.user)
        .where(
            AuthToken.token_hash == token_digest,
            AuthToken.revoked_at.is_(None),
            AuthToken.expires_at > now,
            UserAccount.is_active == True,  # noqa: E712
        )
    )
    auth_token = result.scalar_one_or_none()
    return auth_token.user if auth_token else None

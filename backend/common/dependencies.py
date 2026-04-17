import uuid
from typing import Annotated

from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from common.exceptions import UnauthorizedError
from database import get_db

bearer_scheme = HTTPBearer(auto_error=False)


async def get_current_user(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer_scheme)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> "User":  # type: ignore[name-defined]  # noqa: F821
    """
    Decode the Bearer JWT, load the user from DB, and return it.
    Raises UnauthorizedError (401) on any failure.

    Import note: auth.service and users.models are imported inside the function
    body to avoid a circular dependency between common/ and those modules.
    """
    if credentials is None:
        raise UnauthorizedError()

    # Late imports to break common → users/auth circular dependency
    from auth.service import decode_access_token
    from users.models import User

    user_id_str = await decode_access_token(credentials.credentials)

    try:
        user_id = uuid.UUID(user_id_str)
    except ValueError:
        raise UnauthorizedError("Malformed user ID in token")

    result = await db.execute(
        select(User).where(User.id == user_id, User.deleted_at.is_(None))
    )
    user = result.scalar_one_or_none()
    if user is None:
        raise UnauthorizedError("User not found or deleted")

    return user

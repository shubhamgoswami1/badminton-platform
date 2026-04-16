from typing import Annotated

from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.ext.asyncio import AsyncSession

from common.exceptions import UnauthorizedError
from database import get_db

bearer_scheme = HTTPBearer(auto_error=False)


async def get_current_user(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer_scheme)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> "User":  # type: ignore[name-defined]  # noqa: F821
    """
    Decode JWT, load user from DB, raise 401 on any failure.
    Fully implemented in P1 once the User model and auth service exist.
    """
    if credentials is None:
        raise UnauthorizedError()
    # Placeholder — real implementation added in P1 (auth module)
    raise UnauthorizedError("Auth not yet implemented — this stub will be replaced in P1")

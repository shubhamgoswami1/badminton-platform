from typing import Annotated

from fastapi import APIRouter, Depends
from fastapi.responses import JSONResponse

from common.dependencies import get_current_user
from common.response import ok

router = APIRouter(tags=["health"])


@router.get("/health", response_class=JSONResponse, status_code=200)
async def get_health(
    _current_user: Annotated[object, Depends(get_current_user)],
) -> dict:
    """
    Liveness check. Requires a valid Bearer token.
    Used in P1 tests to verify get_current_user resolves correctly.
    """
    return ok({"status": "ok"})

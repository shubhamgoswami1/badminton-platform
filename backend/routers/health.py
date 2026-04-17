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
    """Authenticated liveness check — used in auth tests to verify get_current_user."""
    return ok({"status": "ok"})


@router.get("/health/live", response_class=JSONResponse, status_code=200)
async def get_health_live() -> dict:
    """Unauthenticated liveness probe — safe for Docker HEALTHCHECK and load balancers."""
    return ok({"status": "ok"})

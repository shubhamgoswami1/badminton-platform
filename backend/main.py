import structlog
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from common.exceptions import AppError
from common.response import error
from config import get_settings
from logging_config import configure_logging
from routers.health import router as health_router

settings = get_settings()
configure_logging()
log = structlog.get_logger()


def create_app() -> FastAPI:
    app = FastAPI(
        title="Badminton Platform API",
        version="0.1.0",
        docs_url="/docs" if settings.is_development else None,
        redoc_url="/redoc" if settings.is_development else None,
    )

    # ── CORS ─────────────────────────────────────────────────
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins_list,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # ── Exception handlers ────────────────────────────────────
    @app.exception_handler(AppError)
    async def app_error_handler(request: Request, exc: AppError) -> JSONResponse:
        return JSONResponse(
            status_code=exc.status_code,
            content=error(exc.code, exc.message),
        )

    @app.exception_handler(Exception)
    async def unhandled_error_handler(request: Request, exc: Exception) -> JSONResponse:
        log.error("unhandled_exception", exc_info=exc, path=request.url.path)
        return JSONResponse(
            status_code=500,
            content=error("INTERNAL_ERROR", "An unexpected error occurred"),
        )

    # ── Routers ───────────────────────────────────────────────
    app.include_router(health_router, prefix="/api/v1")

    # Business module routers are registered here as they are implemented:
    # from auth.router import router as auth_router
    # app.include_router(auth_router, prefix="/api/v1")
    # from users.router import router as users_router
    # app.include_router(users_router, prefix="/api/v1")

    return app


app = create_app()

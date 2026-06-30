import structlog
from contextlib import asynccontextmanager
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from common.exceptions import AppError
from common.middleware import RequestIdMiddleware
from common.response import error
from config import get_settings
from logging_config import configure_logging
from routers.health import router as health_router

settings = get_settings()
configure_logging()
log = structlog.get_logger()


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Auto-create all tables on startup so fresh deployments work without
    # a separate migration step.
    from database import Base, engine
    from admin.models import AdminLog  # noqa: F401
    from auth.models import OtpVerification, RefreshToken  # noqa: F401
    from common.models import IdempotencyRecord  # noqa: F401
    from discovery.models import Venue  # noqa: F401
    from tournaments.models import Tournament, TournamentParticipant, Team, Match, MatchScore  # noqa: F401
    from training.models import TrainingLog, TrainingGoal  # noqa: F401
    from users.models import User, PlayerProfile  # noqa: F401

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    log.info("database_tables_ready")
    yield


def create_app() -> FastAPI:
    app = FastAPI(
        lifespan=lifespan,
        title="Badminton Platform API",
        version="0.1.0",
        docs_url="/docs" if settings.is_development else None,
        redoc_url="/redoc" if settings.is_development else None,
    )

    # ── Middleware ────────────────────────────────────────────
    app.add_middleware(RequestIdMiddleware)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins_list,
        allow_credentials=False,
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
    from auth.router import router as auth_router
    from users.router import router as users_router
    from tournaments.router import router as tournaments_router
    from scores.router import router as scores_router
    from training.router import router as training_router
    from discovery.router import router as discovery_router
    from admin.router import router as admin_router

    app.include_router(health_router, prefix="/api/v1")
    app.include_router(auth_router, prefix="/api/v1")
    app.include_router(users_router, prefix="/api/v1")
    app.include_router(tournaments_router, prefix="/api/v1")
    app.include_router(scores_router, prefix="/api/v1")
    app.include_router(training_router, prefix="/api/v1")
    app.include_router(discovery_router, prefix="/api/v1")
    app.include_router(admin_router, prefix="/api/v1")

    return app


app = create_app()

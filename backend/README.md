# Badminton Platform — Backend

FastAPI + SQLAlchemy 2 (async) + PostgreSQL 15 + Alembic.

---

## Prerequisites

- Python 3.11+
- PostgreSQL 15 running locally (or use Docker Compose)
- `pip` or a virtual environment manager

---

## Quick Start (local, no Docker)

```bash
# 1. Create and activate a virtual environment
python3.11 -m venv .venv
source .venv/bin/activate

# 2. Install dependencies
pip install -r requirements.txt

# 3. Copy env file and edit as needed
cp .env.example .env

# 4. Create the database (if not using Docker)
createdb badminton          # or psql -c "CREATE DATABASE badminton;"

# 5. Run migrations
alembic upgrade head

# 6. Start the dev server
uvicorn main:app --reload
```

API is available at <http://localhost:8000>.  
Interactive docs: <http://localhost:8000/docs>

---

## Quick Start (Docker Compose)

```bash
# From the repo root (one level above backend/)
cp backend/.env.example backend/.env
docker compose up --build
```

This starts:
- `postgres` on port `5432`
- `backend` on port `8000` with hot-reload

Run migrations inside the container:

```bash
docker compose exec backend alembic upgrade head
```

---

## Environment Variables

All variables are read from `.env` (see `.env.example` for defaults).

| Variable | Required | Default | Description |
|---|---|---|---|
| `DATABASE_URL` | yes | `postgresql+asyncpg://badminton:badminton@localhost:5432/badminton` | Async PostgreSQL connection string |
| `APP_ENV` | no | `development` | `development` / `staging` / `production` |
| `JWT_SECRET_KEY` | yes (prod) | `change-me-…` | HS256 signing secret — **must be changed in production** |
| `JWT_ACCESS_TOKEN_EXPIRE_MINUTES` | no | `15` | Access token lifetime |
| `JWT_REFRESH_TOKEN_EXPIRE_DAYS` | no | `30` | Refresh token lifetime |
| `OTP_MOCK_MODE` | no | `true` | `true` → OTP is always `123456`; no SMS sent |
| `OTP_TTL_MINUTES` | no | `10` | OTP expiry window |
| `CORS_ORIGINS` | no | `*` | Comma-separated allowed origins; use `*` for dev only |

---

## Running Tests

```bash
# Create the test database first
createdb badminton_test

# Run all tests
pytest

# Run with verbose output
pytest -v

# Run a specific file
pytest tests/test_health.py
```

Tests use a real PostgreSQL database (`badminton_test` by default).  
Set `TEST_DATABASE_URL` to override.

---

## Migrations

```bash
# Apply all pending migrations
alembic upgrade head

# Create a new migration (auto-detect model changes)
alembic revision --autogenerate -m "short description"

# Roll back one step
alembic downgrade -1

# Roll back to base (empty DB)
alembic downgrade base
```

Migration files live in `alembic/versions/`.

---

## Project Structure

```
backend/
├── main.py               # App factory — registers middleware, exception handlers, routers
├── config.py             # Pydantic BaseSettings (reads from .env)
├── database.py           # Async engine, session factory, DeclarativeBase
├── logging_config.py     # structlog setup (dev: console, prod: JSON)
├── alembic.ini           # Alembic config
├── alembic/
│   ├── env.py            # Async migration runner
│   ├── script.py.mako    # Migration file template
│   └── versions/         # Generated migration files
├── routers/
│   └── health.py         # GET /api/v1/health
├── common/
│   ├── enums.py          # All shared enums (TournamentStatus, MatchStatus, …)
│   ├── exceptions.py     # AppError hierarchy (NotFoundError, ForbiddenError, …)
│   ├── response.py       # ok() / error() envelope helpers
│   ├── pagination.py     # PageParams, paginate()
│   └── dependencies.py   # get_db, get_current_user (auth stub — implemented in P1)
├── auth/                 # P1 — OTP, JWT, token refresh, logout
├── users/                # P2 — User + PlayerProfile CRUD
├── tournaments/          # P3–P5, P7 — Tournament lifecycle, bracket generation
│   └── bracket/          # Pure bracket generation logic (no DB calls)
├── scores/               # P6 — Score submission, match advancement
├── training/             # P8–P9 — Training logs and goals
├── discovery/            # P10 — Player/tournament/venue discovery
├── scripts/
│   └── seed_dev.py       # Dev seed data (populated from P1 onwards)
├── tests/
│   ├── conftest.py       # Shared fixtures (async client, DB session)
│   └── test_health.py    # P0 smoke test
├── Dockerfile
├── requirements.txt
└── .env.example
```

---

## Assumptions

1. **Python 3.11+** — uses `X | Y` union syntax and `match` statement compatibility.
2. **asyncpg** is the async PostgreSQL driver. The `DATABASE_URL` must use the `postgresql+asyncpg://` scheme.
3. **OTP mock mode** is `true` by default — no SMS provider is wired up. Flip to `false` and add an SMS adapter in `auth/sms.py` when ready.
4. **No Redis** — all state lives in PostgreSQL. Rate limiting is handled in application logic via the `otp_verifications` table.
5. **CORS** defaults to `*` for local development. Set explicit origins before production deployment.
6. **JWT secret** — the default value in `.env.example` must be replaced with a cryptographically random string (e.g. `openssl rand -hex 32`) before any staging or production deployment.

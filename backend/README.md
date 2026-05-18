# Badminton Platform — Backend

FastAPI · SQLAlchemy 2 (async) · PostgreSQL 15 · Alembic

---

## Quick Start (local, no Docker)

```bash
# 1. Create and activate a virtual environment
python3.11 -m venv .venv
source .venv/bin/activate      # Windows: .venv\Scripts\activate

# 2. Install dependencies
pip install -r requirements.txt

# 3. Copy env file
cp .env.example .env
# Edit .env if your Postgres credentials differ from the defaults

# 4. Create databases
createdb badminton
createdb badminton_test        # needed only for tests

# 5. Apply migrations
alembic upgrade head

# 6. Seed demo data (optional but recommended for development)
python scripts/seed_dev.py

# 7. Start the dev server
uvicorn main:app --reload
```

API root: <http://localhost:8000>  
Interactive docs: <http://localhost:8000/docs>

---

## Quick Start (Docker Compose)

```bash
# From the repo root (one level above backend/)
cp backend/.env.example backend/.env
docker compose up --build

# In a second terminal — apply migrations
docker compose exec backend alembic upgrade head

# Seed demo data
docker compose exec backend python scripts/seed_dev.py
```

---

## Demo Accounts (after seeding)

OTP mock mode is **on by default** — every phone number accepts the code `123456`.  
No SMS is sent.

| Phone | Name | Skill | City | Role |
|---|---|---|---|---|
| +919876500001 | Rahul Sharma | ADVANCED | Mumbai | Admin + Player |
| +919876500002 | Priya Patel | INTERMEDIATE | Delhi | Player |
| +919876500003 | Arjun Kumar | ADVANCED | Bangalore | Player |
| +919876500004 | Kavya Nair | PROFESSIONAL | Hyderabad | Player |
| +919876500005 | Vikram Singh | INTERMEDIATE | Chennai | Player |
| +919876500006 | Ananya Reddy | BEGINNER | Pune | Player |
| +919876500007 | Rohit Gupta | ADVANCED | Mumbai | Player |
| +919876500008 | Deepa Iyer | INTERMEDIATE | Bangalore | Player |
| +919876500009 | Sanjay Joshi | ADVANCED | Delhi | Player |
| +919876500010 | Meera Shah | PROFESSIONAL | Mumbai | Organiser + Player |

The seed also creates four tournaments:
- **Mumbai Open 2026** — COMPLETED, 8-player knockout (all matches done, Elo applied)
- **Bangalore Invitational** — IN_PROGRESS, 4-player knockout (final live with partial score)
- **Delhi Spring Cup 2026** — REGISTRATION_OPEN (3 players joined, 1 slot free)
- **Chennai Masters 2026** — DRAFT

---

## Authentication Flow

All protected endpoints require a JWT Bearer token. Tokens are obtained via OTP:

```bash
# Step 1 — request OTP  (returns null body in mock mode; OTP is always 123456)
curl -s -X POST http://localhost:8000/api/v1/auth/otp/request \
  -H "Content-Type: application/json" \
  -d '{"phone_number": "+919876500001"}' | jq

# Step 2 — verify OTP → get tokens
curl -s -X POST http://localhost:8000/api/v1/auth/otp/verify \
  -H "Content-Type: application/json" \
  -d '{"phone_number": "+919876500001", "otp": "123456"}' | jq

# Copy access_token from the response, then use it:
export TOKEN="<access_token>"
```

---

## Sample API Calls

All responses use the envelope `{"data": ..., "error": null, "meta": {}}`.

### Profile

```bash
# View your profile
curl -s http://localhost:8000/api/v1/users/me \
  -H "Authorization: Bearer $TOKEN" | jq

# Update profile
curl -s -X PUT http://localhost:8000/api/v1/users/me/profile \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"display_name": "Rahul Sharma", "city": "Mumbai", "skill_level": "ADVANCED"}' | jq
```

### Tournaments

```bash
# List all tournaments
curl -s http://localhost:8000/api/v1/tournaments | jq

# List tournaments in your city
curl -s "http://localhost:8000/api/v1/tournaments?city=Mumbai" | jq

# Create a tournament
curl -s -X POST http://localhost:8000/api/v1/tournaments \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "My Cup",
    "format": "KNOCKOUT",
    "match_format": "BEST_OF_3",
    "play_type": "SINGLES",
    "city": "Mumbai"
  }' | jq

# Open registration
export TID="<tournament_id>"
curl -s -X POST http://localhost:8000/api/v1/tournaments/$TID/status \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"next_status": "REGISTRATION_OPEN"}' | jq

# Join a tournament (as any player)
curl -s -X POST http://localhost:8000/api/v1/tournaments/$TID/participants \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{}' | jq
```

### Scores

```bash
# List your matches (across all tournaments)
curl -s http://localhost:8000/api/v1/matches/my \
  -H "Authorization: Bearer $TOKEN" | jq

# Update scores mid-match (PENDING → IN_PROGRESS)
export MID="<match_id>"
curl -s -X POST http://localhost:8000/api/v1/matches/$MID/update-score \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "sets": [{"set_number": 1, "side_a_score": 15, "side_b_score": 10}],
    "client_updated_at": "2026-01-01T10:00:00Z"
  }' | jq

# Complete a match
export WINNER_ID="<participant_id>"
curl -s -X POST http://localhost:8000/api/v1/matches/$MID/complete \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "winner_participant_id": "'$WINNER_ID'",
    "sets": [
      {"set_number": 1, "side_a_score": 21, "side_b_score": 15},
      {"set_number": 2, "side_a_score": 21, "side_b_score": 18}
    ]
  }' | jq
```

### Player Discovery

```bash
# Search players by name
curl -s "http://localhost:8000/api/v1/discovery/players?q=rahul" \
  -H "Authorization: Bearer $TOKEN" | jq

# Filter by skill level and Elo range
curl -s "http://localhost:8000/api/v1/discovery/players?skill_level=ADVANCED&elo_min=1600&elo_max=1800" \
  -H "Authorization: Bearer $TOKEN" | jq
```

### Training

```bash
# Log a training session
curl -s -X POST http://localhost:8000/api/v1/training/logs \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "session_type": "PRACTICE",
    "duration_minutes": 90,
    "intensity": "HIGH",
    "notes": "Worked on smash accuracy"
  }' | jq

# Create a training goal
curl -s -X POST http://localhost:8000/api/v1/training/goals \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Win local tournament",
    "description": "Enter and win the next city-level knockout.",
    "target_date": "2026-08-01T00:00:00Z"
  }' | jq
```

### Admin

```bash
# Requires an account with is_admin=true (Rahul Sharma, +919876500001 after seed)
# Get admin access token first, then:

# Ban a user
curl -s -X POST http://localhost:8000/api/v1/admin/ban-user \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"user_id": "<user_id>", "notes": "Reason for ban"}' | jq

# View audit log
curl -s "http://localhost:8000/api/v1/admin/logs" \
  -H "Authorization: Bearer $ADMIN_TOKEN" | jq

# Filter audit log by action
curl -s "http://localhost:8000/api/v1/admin/logs?action=BAN_USER" \
  -H "Authorization: Bearer $ADMIN_TOKEN" | jq
```

---

## Environment Variables

All variables are read from `.env` (copy `.env.example` to get started).

| Variable | Default | Description |
|---|---|---|
| `DATABASE_URL` | `postgresql+asyncpg://badminton:badminton@localhost:5432/badminton` | Async PostgreSQL URL |
| `APP_ENV` | `development` | `development` / `staging` / `production` |
| `JWT_SECRET_KEY` | `change-me-…` | HS256 signing key — **change before staging/prod** |
| `JWT_ACCESS_TOKEN_EXPIRE_MINUTES` | `15` | Access token lifetime |
| `JWT_REFRESH_TOKEN_EXPIRE_DAYS` | `30` | Refresh token lifetime |
| `OTP_MOCK_MODE` | `true` | `true` → always accept `123456`; no SMS sent |
| `OTP_TTL_MINUTES` | `10` | OTP expiry window |
| `CORS_ORIGINS` | `*` | Comma-separated origins; `*` = allow all (dev only) |

---

## Running Tests

```bash
# Ensure the test database exists
createdb badminton_test

# Run all tests
pytest

# Verbose output
pytest -v

# Single module
pytest tests/test_admin.py -v

# Stop on first failure
pytest -x
```

Tests use a real PostgreSQL database (`badminton_test` by default).  
Override with `TEST_DATABASE_URL=postgresql+asyncpg://...` in your shell.

---

## Migrations

```bash
# Apply all pending migrations
alembic upgrade head

# Roll back one step
alembic downgrade -1

# Roll back to empty DB
alembic downgrade base

# Auto-generate a migration after model changes
alembic revision --autogenerate -m "add foo column"
```

Migration files live in `alembic/versions/`. Each file is numbered (`0001_`, `0002_`, …) for easy ordering.

---

## Project Structure

```
backend/
├── main.py               # App factory — middleware, exception handlers, routers
├── config.py             # Pydantic BaseSettings (reads .env)
├── database.py           # Async engine, session factory, DeclarativeBase
├── logging_config.py     # structlog (console in dev, JSON in prod)
├── alembic.ini
├── alembic/
│   ├── env.py            # Async migration runner
│   └── versions/         # 0001 … 0020 migration files
├── routers/
│   └── health.py         # GET /api/v1/health
├── common/
│   ├── enums.py          # Shared enums (TournamentStatus, MatchStatus, …)
│   ├── exceptions.py     # AppError hierarchy (NotFoundError, ForbiddenError, …)
│   ├── response.py       # ok() / error() envelope helpers
│   ├── pagination.py     # PageParams, paginate()
│   └── dependencies.py   # get_db, get_current_user, get_current_admin
├── auth/                 # OTP request/verify, JWT issue/refresh, logout
├── users/                # User + PlayerProfile CRUD
├── tournaments/          # Tournament lifecycle, participant registration,
│   └── bracket/          # bracket generation (knockout + round-robin)
├── scores/               # Score submission, match advancement, Elo, conflict handling
├── training/             # Training logs and goals
├── discovery/            # Player/tournament/venue search
├── admin/                # Ban/unban user, delete tournament, audit log
├── scripts/
│   └── seed_dev.py       # Realistic dev seed (10 players, 4 tournaments, training data)
└── tests/
    ├── conftest.py        # Async client + DB session fixtures
    ├── test_health.py
    ├── test_auth.py
    ├── test_auth_hardening.py
    ├── test_users.py
    ├── test_tournaments.py
    ├── test_participants.py
    ├── test_bracket_knockout.py
    ├── test_bracket_round_robin.py
    ├── test_scores.py
    ├── test_elo.py
    ├── test_my_matches.py
    ├── test_auto_complete.py
    ├── test_standings_ordering.py
    ├── test_discovery.py
    ├── test_discovery_search.py
    ├── test_training_logs.py
    ├── test_training_goals.py
    ├── test_sync_conflict.py
    └── test_admin.py
```

---

## Notes

- **OTP mock mode** (`OTP_MOCK_MODE=true`) is on by default. The code is always `123456`. Switch to `false` and implement `auth/sms.py` when integrating a real SMS provider.
- **JWT secret** — the `.env.example` default must be replaced with a cryptographically random string (`openssl rand -hex 32`) before any non-local deployment.
- **asyncpg** is the async PostgreSQL driver. `DATABASE_URL` must use the `postgresql+asyncpg://` scheme.
- **No Redis** — all state lives in PostgreSQL. OTP rate limiting is enforced via the `otp_verifications` table.
- **Soft deletes** — tournaments and users use a `deleted_at` timestamp rather than hard deletes.
- **Admin** — the first admin must be promoted directly in the DB (`UPDATE users SET is_admin = true WHERE phone_number = '...'`), or it's created automatically by `seed_dev.py` for Rahul Sharma (+919876500001).

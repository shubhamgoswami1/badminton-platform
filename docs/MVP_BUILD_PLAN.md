# Badminton Platform — MVP Build Plan

**Version:** 1.0  
**Date:** April 2026  
**Scope:** Architecture planning only — no code generated

---

## Table of Contents

1. [MVP Assumptions](#1-mvp-assumptions)
2. [Architecture Decisions](#2-architecture-decisions)
3. [Backend — Module Boundaries](#3-backend--module-boundaries)
4. [Backend — Folder Structure](#4-backend--folder-structure)
5. [Flutter — Feature/Module Boundaries](#5-flutter--featuremodule-boundaries)
6. [Flutter — Folder Structure](#6-flutter--folder-structure)
7. [Database Entities and Relationships](#7-database-entities-and-relationships)
8. [Status Enums and State Transitions](#8-status-enums-and-state-transitions)
9. [Core API Surface](#9-core-api-surface)
10. [Auth Approach](#10-auth-approach)
11. [Offline Score Sync Approach](#11-offline-score-sync-approach)
12. [Tournament Generation Approach](#12-tournament-generation-approach)
13. [Business Rules](#13-business-rules)
14. [Coding Conventions](#14-coding-conventions)
15. [Testing Priorities](#15-testing-priorities)
16. [Phased Implementation Order](#16-phased-implementation-order)

---

## 1. MVP Assumptions

### User and Identity
- A user registers via mobile number + OTP only. Email is not supported in MVP.
- One phone number = one account. No account merging.
- In dev/mock mode, OTP is always `123456`. No actual SMS is sent.
- A user has a single player profile. No multi-profile or team accounts.
- Profile photo upload is deferred to Phase 2. Avatar is text-initials only in MVP.

### Geography and Discovery
- "Nearby" discovery is based on a user-supplied city string, not GPS coordinates. GPS-based proximity is post-MVP.
- Venue data is user-submitted text (name + city + optional address). No map integration in MVP.

### Tournaments
- A tournament supports exactly two formats: Knockout (single elimination) and Round Robin.
- Doubles is supported (a match has two players per side). Singles is also supported. Mixed doubles is treated identically to doubles — no gender enforcement logic in MVP.
- Tournament brackets are generated once when the organiser clicks "Generate Bracket." They are not regenerated unless the organiser explicitly resets (which is only allowed before any match is played).
- Seeding is manual: the organiser orders participants before generation. If no order is set, participants are shuffled randomly.
- Maximum participants per tournament: 64 (knockout), 16 (round robin). These are soft limits enforced by validation, not schema constraints.
- A tournament must have at least 4 participants before bracket generation is allowed.
- Byes in knockout are filled from the bottom of the bracket. A player who receives a bye auto-advances.
- There is no third-place match in knockout for MVP.
- Round robin has no tiebreaker logic beyond points. In case of a tie in points, the tied players share the position. Detailed set/game tiebreakers are post-MVP.

### Scoring
- A match score is recorded as sets. Each set has a score pair (e.g., 21–15). No real-time rally-by-rally tracking.
- The number of sets per match is configured at tournament level (best of 1, 3, or 5).
- Score submission is done by either participant or the organiser. There is no dispute system in MVP — the last accepted submission wins.
- Scores can be edited only by the organiser after submission.

### Training Logs and Goals
- Training logs are personal and private. No social sharing of training logs in MVP.
- A goal has a target (numeric), a metric (e.g., "sessions per week", "km run"), and a deadline. Progress is manually updated by the user.
- No AI-generated training plans in MVP.

### Notifications
- No push notifications in MVP. The app polls or refreshes on demand.
- In-app notification feed is post-MVP.

### Payments
- No payment gateway in MVP. Tournament entry is free or honour-based.

### Platform
- Android and iOS via Flutter. Web is post-MVP.
- Minimum Android SDK: 21. Minimum iOS: 13.

---

## 2. Architecture Decisions

### Overall Style
- **Modular monolith.** All backend modules live in a single FastAPI process and single PostgreSQL database. Module boundaries are enforced through folder structure and import discipline, not network boundaries.
- **No microservices.** No service mesh, no inter-service HTTP calls, no message broker in MVP.
- **No Redis.** All state in PostgreSQL. Rate limiting, if needed, is done with a simple in-memory counter at the process level or deferred entirely.

### Backend
| Concern | Decision |
|---|---|
| Framework | FastAPI (Python 3.11+) |
| ORM | SQLAlchemy 2.x (async, Core + ORM mixed) |
| Migrations | Alembic |
| Auth tokens | JWT (HS256), access + refresh token pair |
| Password/OTP store | Hashed OTP in `otp_verifications` table, TTL enforced in app logic |
| Background jobs | FastAPI BackgroundTasks for lightweight async work (e.g., bracket generation). No Celery in MVP. |
| File storage | Local disk in dev, S3-compatible bucket (e.g., Cloudflare R2) in prod — behind a thin storage abstraction. Profile photos deferred to Phase 2. |
| Config management | Pydantic `BaseSettings` with `.env` file |
| Logging | Python `structlog` with JSON output |
| CORS | Configured explicitly; allow only known origins in prod |
| API versioning | All routes prefixed `/api/v1/`. No version negotiation complexity. |

### Flutter
| Concern | Decision |
|---|---|
| State management | Riverpod (code-gen variant) |
| Navigation | go_router |
| HTTP client | Dio with interceptors for JWT refresh |
| Local storage | Hive for offline queue + SharedPreferences for simple flags |
| Offline sync | Local Hive queue, drained on connectivity restore |
| Forms | reactive_forms |
| Theming | Material 3, custom color scheme, no third-party UI kit |

### Database
- Single PostgreSQL 15+ database.
- All tables use UUID primary keys (gen_random_uuid()).
- All timestamps are `TIMESTAMPTZ` stored in UTC.
- Soft deletes via `deleted_at TIMESTAMPTZ` on key entities (users, tournaments). Hard deletes for operational/log records.
- No database-level row-level security for MVP. Access control is purely in application layer.

---

## 3. Backend — Module Boundaries

Each module owns its own models, schemas (Pydantic), service layer, and router. Cross-module calls go through the service layer only — never by importing another module's models directly in a router.

### Modules

#### `auth`
Responsibilities: OTP generation, OTP verification, JWT issuance, token refresh, logout (token revocation via blocklist table).

Owns: `otp_verifications`, `refresh_tokens` tables.

#### `users`
Responsibilities: User CRUD, player profile management, profile photo (Phase 2), city/location preference.

Owns: `users`, `player_profiles` tables.

#### `tournaments`
Responsibilities: Tournament creation, participant registration, bracket generation, match scheduling, tournament lifecycle management.

Owns: `tournaments`, `tournament_participants`, `matches`, `match_scores` tables.

#### `scores`
Responsibilities: Score submission, score validation, score edit (organiser), match result computation.

Depends on `tournaments` module (reads match context). Owns no additional tables — writes into `match_scores` and updates `matches`.

#### `training`
Responsibilities: Training session logs, training goals, goal progress updates.

Owns: `training_logs`, `training_goals` tables.

#### `discovery`
Responsibilities: Player discovery by city, tournament discovery by city and status, venue listing.

Owns: `venues` table. Queries `users` and `tournaments` read-only.

#### `common`
Responsibilities: Shared utilities — pagination helpers, response envelope, error classes, base model mixins, dependency injection providers (DB session, current user).

No tables. No router.

---

## 4. Backend — Folder Structure

```
backend/
├── main.py                        # FastAPI app factory, router registration
├── config.py                      # Pydantic BaseSettings
├── database.py                    # Async engine, session factory
├── alembic/
│   ├── env.py
│   └── versions/
├── common/
│   ├── dependencies.py            # get_db, get_current_user
│   ├── exceptions.py              # AppError, NotFoundError, ForbiddenError
│   ├── pagination.py              # PageParams, PagedResponse
│   ├── response.py                # Standard envelope: {data, error, meta}
│   └── enums.py                   # Shared enums (MatchFormat, TournamentFormat, etc.)
├── auth/
│   ├── router.py
│   ├── service.py
│   ├── schemas.py
│   └── models.py                  # OtpVerification, RefreshToken
├── users/
│   ├── router.py
│   ├── service.py
│   ├── schemas.py
│   └── models.py                  # User, PlayerProfile
├── tournaments/
│   ├── router.py
│   ├── service.py
│   ├── schemas.py
│   ├── models.py                  # Tournament, TournamentParticipant, Match, MatchScore
│   └── bracket/
│       ├── knockout.py            # Knockout bracket generation logic
│       └── round_robin.py         # Round robin schedule generation logic
├── scores/
│   ├── router.py
│   ├── service.py
│   └── schemas.py
├── training/
│   ├── router.py
│   ├── service.py
│   ├── schemas.py
│   └── models.py                  # TrainingLog, TrainingGoal
├── discovery/
│   ├── router.py
│   ├── service.py
│   ├── schemas.py
│   └── models.py                  # Venue
└── tests/
    ├── conftest.py
    ├── test_auth.py
    ├── test_tournaments.py
    ├── test_scores.py
    ├── test_bracket_knockout.py
    └── test_bracket_round_robin.py
```

---

## 5. Flutter — Feature/Module Boundaries

Each feature is a self-contained folder with its own providers, screens, widgets, and repository. Features communicate via shared providers or by navigating with go_router — never by importing each other's internal widgets.

### Features

| Feature | Responsibility |
|---|---|
| `auth` | OTP entry flow, JWT storage, login state |
| `profile` | View/edit own profile, view other player profiles |
| `tournaments` | Browse tournaments, create tournament, manage participants |
| `bracket` | View knockout bracket tree, view round robin table |
| `matches` | View match detail, submit score, view score history |
| `training` | Log training sessions, set goals, view progress |
| `discovery` | Discover players and tournaments by city |
| `home` | Dashboard — upcoming matches, recent activity summary |

### Shared Layers

| Layer | Contents |
|---|---|
| `core/network` | Dio client, JWT interceptor, refresh logic |
| `core/storage` | Hive boxes, SharedPreferences wrappers |
| `core/sync` | Offline queue manager |
| `core/theme` | Color scheme, text styles, spacing constants |
| `core/widgets` | Shared UI components (AppButton, AppTextField, EmptyState, LoadingOverlay) |
| `core/utils` | Date formatting, string helpers, validators |
| `core/router` | go_router config, route guards |

---

## 6. Flutter — Folder Structure

```
lib/
├── main.dart
├── app.dart                        # MaterialApp + Riverpod ProviderScope
├── core/
│   ├── network/
│   │   ├── dio_client.dart
│   │   ├── auth_interceptor.dart
│   │   └── api_endpoints.dart
│   ├── storage/
│   │   ├── hive_boxes.dart
│   │   └── prefs.dart
│   ├── sync/
│   │   └── offline_queue.dart
│   ├── theme/
│   │   ├── app_theme.dart
│   │   └── app_colors.dart
│   ├── widgets/
│   │   ├── app_button.dart
│   │   ├── app_text_field.dart
│   │   ├── empty_state.dart
│   │   └── loading_overlay.dart
│   ├── utils/
│   │   ├── date_utils.dart
│   │   └── validators.dart
│   └── router/
│       ├── app_router.dart
│       └── route_guards.dart
├── features/
│   ├── auth/
│   │   ├── data/
│   │   │   └── auth_repository.dart
│   │   ├── providers/
│   │   │   └── auth_provider.dart
│   │   └── screens/
│   │       ├── phone_entry_screen.dart
│   │       └── otp_screen.dart
│   ├── profile/
│   │   ├── data/
│   │   ├── providers/
│   │   └── screens/
│   │       ├── my_profile_screen.dart
│   │       └── player_profile_screen.dart
│   ├── tournaments/
│   │   ├── data/
│   │   ├── providers/
│   │   └── screens/
│   │       ├── tournament_list_screen.dart
│   │       ├── tournament_detail_screen.dart
│   │       └── create_tournament_screen.dart
│   ├── bracket/
│   │   ├── providers/
│   │   └── screens/
│   │       ├── knockout_bracket_screen.dart
│   │       └── round_robin_table_screen.dart
│   ├── matches/
│   │   ├── data/
│   │   ├── providers/
│   │   └── screens/
│   │       ├── match_detail_screen.dart
│   │       └── score_submit_screen.dart
│   ├── training/
│   │   ├── data/
│   │   ├── providers/
│   │   └── screens/
│   │       ├── training_log_screen.dart
│   │       ├── add_log_screen.dart
│   │       ├── goals_screen.dart
│   │       └── add_goal_screen.dart
│   ├── discovery/
│   │   ├── data/
│   │   ├── providers/
│   │   └── screens/
│   │       └── discovery_screen.dart
│   └── home/
│       ├── providers/
│       └── screens/
│           └── home_screen.dart
```

---

## 7. Database Entities and Relationships

### Entity List

#### `users`
```
id                  UUID PK
phone_number        TEXT UNIQUE NOT NULL
is_verified         BOOLEAN DEFAULT FALSE
created_at          TIMESTAMPTZ
updated_at          TIMESTAMPTZ
deleted_at          TIMESTAMPTZ
```

#### `player_profiles`
```
id                  UUID PK
user_id             UUID FK → users.id UNIQUE
display_name        TEXT NOT NULL
city                TEXT
skill_level         TEXT  -- BEGINNER | INTERMEDIATE | ADVANCED | PROFESSIONAL
play_style          TEXT  -- SINGLES | DOUBLES | BOTH
bio                 TEXT
created_at          TIMESTAMPTZ
updated_at          TIMESTAMPTZ
```

#### `otp_verifications`
```
id                  UUID PK
phone_number        TEXT NOT NULL
otp_hash            TEXT NOT NULL
expires_at          TIMESTAMPTZ NOT NULL
used_at             TIMESTAMPTZ
created_at          TIMESTAMPTZ
```

#### `refresh_tokens`
```
id                  UUID PK
user_id             UUID FK → users.id
token_hash          TEXT NOT NULL UNIQUE
issued_at           TIMESTAMPTZ
expires_at          TIMESTAMPTZ
revoked_at          TIMESTAMPTZ
```

#### `venues`
```
id                  UUID PK
submitted_by        UUID FK → users.id
name                TEXT NOT NULL
city                TEXT NOT NULL
address             TEXT
created_at          TIMESTAMPTZ
```

#### `tournaments`
```
id                  UUID PK
organiser_id        UUID FK → users.id
title               TEXT NOT NULL
description         TEXT
city                TEXT
venue_id            UUID FK → venues.id  -- nullable
format              TEXT  -- KNOCKOUT | ROUND_ROBIN
match_format        TEXT  -- BEST_OF_1 | BEST_OF_3 | BEST_OF_5
play_type           TEXT  -- SINGLES | DOUBLES | MIXED_DOUBLES
status              TEXT  -- DRAFT | REGISTRATION_OPEN | REGISTRATION_CLOSED | IN_PROGRESS | COMPLETED | CANCELLED
max_participants    INTEGER
registration_deadline TIMESTAMPTZ
starts_at           TIMESTAMPTZ
bracket_generated   BOOLEAN DEFAULT FALSE
created_at          TIMESTAMPTZ
updated_at          TIMESTAMPTZ
deleted_at          TIMESTAMPTZ
```

#### `tournament_participants`
```
id                  UUID PK
tournament_id       UUID FK → tournaments.id
user_id             UUID FK → users.id
partner_user_id     UUID FK → users.id  -- nullable, only for doubles
seed_order          INTEGER  -- organiser-set order for seeding; NULL = unseeded
registered_at       TIMESTAMPTZ
status              TEXT  -- REGISTERED | WITHDRAWN | DISQUALIFIED
UNIQUE (tournament_id, user_id)
```

#### `matches`
```
id                  UUID PK
tournament_id       UUID FK → tournaments.id
round               INTEGER  -- 1-based round number
match_number        INTEGER  -- position within round
side_a_participant_id  UUID FK → tournament_participants.id  -- nullable (bye)
side_b_participant_id  UUID FK → tournament_participants.id  -- nullable (bye)
winner_participant_id  UUID FK → tournament_participants.id  -- nullable until decided
status              TEXT  -- PENDING | IN_PROGRESS | COMPLETED | WALKOVER | BYE
scheduled_at        TIMESTAMPTZ
completed_at        TIMESTAMPTZ
next_match_id       UUID FK → matches.id  -- knockout only; which match winner advances to
created_at          TIMESTAMPTZ
```

#### `match_scores`
```
id                  UUID PK
match_id            UUID FK → matches.id
set_number          INTEGER  -- 1-based
side_a_score        INTEGER
side_b_score        INTEGER
submitted_by        UUID FK → users.id
submitted_at        TIMESTAMPTZ
```

#### `training_logs`
```
id                  UUID PK
user_id             UUID FK → users.id
logged_at           DATE NOT NULL
duration_minutes    INTEGER
session_type        TEXT  -- PRACTICE | FITNESS | MATCH | DRILL | REST
notes               TEXT
created_at          TIMESTAMPTZ
```

#### `training_goals`
```
id                  UUID PK
user_id             UUID FK → users.id
title               TEXT NOT NULL
metric              TEXT  -- e.g. "sessions_per_week", "km_run", "hours_trained"
target_value        NUMERIC
current_value       NUMERIC DEFAULT 0
deadline            DATE
status              TEXT  -- ACTIVE | ACHIEVED | ABANDONED
created_at          TIMESTAMPTZ
updated_at          TIMESTAMPTZ
```

### Key Relationships

```
users ──< player_profiles          (1:1)
users ──< tournaments              (organiser; 1:many)
users ──< tournament_participants  (1:many)
tournaments ──< tournament_participants (1:many)
tournaments ──< matches            (1:many)
tournament_participants ──< matches (side_a, side_b, winner; many:many via match)
matches ──< match_scores           (1:many, one row per set)
users ──< training_logs            (1:many)
users ──< training_goals           (1:many)
users ──< venues                   (submitted_by; 1:many)
```

---

## 8. Status Enums and State Transitions

### Tournament Status

```
DRAFT
  → REGISTRATION_OPEN       (organiser opens registration)
  → CANCELLED               (organiser cancels before any registration)

REGISTRATION_OPEN
  → REGISTRATION_CLOSED     (organiser closes registration, or deadline passes)
  → CANCELLED               (organiser cancels)

REGISTRATION_CLOSED
  → IN_PROGRESS             (organiser generates bracket and starts tournament)
  → REGISTRATION_OPEN       (organiser reopens — only if bracket not yet generated)
  → CANCELLED

IN_PROGRESS
  → COMPLETED               (all matches have a result)
  → CANCELLED               (organiser force-cancels)

COMPLETED → (terminal, no transitions)
CANCELLED → (terminal, no transitions)
```

### Match Status

```
PENDING
  → IN_PROGRESS             (organiser marks match as started, or first score submitted)
  → BYE                     (one side is absent at bracket generation — auto-set)
  → WALKOVER                (one participant withdraws after bracket generated)

IN_PROGRESS
  → COMPLETED               (all required sets submitted and winner determined)
  → WALKOVER                (participant retires mid-match)

BYE       → (terminal, winner auto-set to the present participant)
WALKOVER  → (terminal, winner is the non-withdrawing participant)
COMPLETED → (terminal)
```

### Tournament Participant Status

```
REGISTERED
  → WITHDRAWN      (participant withdraws before tournament starts)
  → DISQUALIFIED   (organiser action during tournament)

WITHDRAWN     → (terminal)
DISQUALIFIED  → (terminal)
```

### Training Goal Status

```
ACTIVE
  → ACHIEVED    (current_value >= target_value, can be auto-set or manually)
  → ABANDONED   (user manually abandons)

ACHIEVED  → ACTIVE   (user resets/continues)
ABANDONED → ACTIVE   (user reactivates)
```

---

## 9. Core API Surface

All routes are prefixed `/api/v1`. All responses use the envelope:
```json
{ "data": {...}, "error": null, "meta": {} }
```
Error responses:
```json
{ "data": null, "error": { "code": "NOT_FOUND", "message": "..." }, "meta": {} }
```

### Auth

```
POST   /auth/otp/request          Body: { phone_number }
POST   /auth/otp/verify           Body: { phone_number, otp } → { access_token, refresh_token }
POST   /auth/token/refresh        Body: { refresh_token } → { access_token }
POST   /auth/logout               Header: Bearer → revokes refresh token
```

### Users / Profiles

```
GET    /users/me                  → own user + profile
PUT    /users/me/profile          Body: { display_name, city, skill_level, play_style, bio }
GET    /users/{user_id}/profile   → public profile
```

### Tournaments

```
POST   /tournaments                        Create tournament
GET    /tournaments                        List (filter: city, status, format)
GET    /tournaments/{id}                   Detail
PUT    /tournaments/{id}                   Update (organiser only, DRAFT/REGISTRATION_OPEN)
DELETE /tournaments/{id}                   Cancel (soft delete, organiser only)
POST   /tournaments/{id}/status            Transition status { next_status }

POST   /tournaments/{id}/participants             Register (self or with partner)
GET    /tournaments/{id}/participants             List participants
DELETE /tournaments/{id}/participants/{pid}       Withdraw participant
PUT    /tournaments/{id}/participants/seed-order  Set seed order { ordered_participant_ids }

POST   /tournaments/{id}/bracket/generate         Generate bracket (organiser only)
GET    /tournaments/{id}/bracket                  Full bracket with matches
GET    /tournaments/{id}/matches                  Flat list of all matches
```

### Matches and Scores

```
GET    /matches/{id}                   Match detail with current scores
PUT    /matches/{id}/status            { next_status } — organiser only
POST   /matches/{id}/scores            Submit set scores { sets: [{set_number, side_a, side_b}] }
PUT    /matches/{id}/scores            Replace all scores (organiser correction only)
```

### Training

```
POST   /training/logs              Create log entry
GET    /training/logs              List own logs (filter: date range, session_type)
GET    /training/logs/{id}         Detail
PUT    /training/logs/{id}         Update
DELETE /training/logs/{id}         Delete

POST   /training/goals             Create goal
GET    /training/goals             List own goals (filter: status)
PUT    /training/goals/{id}        Update (including current_value)
DELETE /training/goals/{id}        Delete
```

### Discovery

```
GET    /discovery/players          Query: city, skill_level, play_style → paginated list
GET    /discovery/tournaments      Query: city, status, format → paginated list
GET    /discovery/venues           Query: city → list
POST   /discovery/venues           Submit a venue
```

### Pagination Convention

All list endpoints accept `?page=1&page_size=20`. Response `meta` includes:
```json
{ "page": 1, "page_size": 20, "total": 143, "total_pages": 8 }
```

### HTTP Status Codes

```
200  OK — successful read or update
201  Created — successful creation
400  Bad Request — validation error
401  Unauthorized — missing or invalid token
403  Forbidden — valid token but insufficient permission
404  Not Found
409  Conflict — duplicate registration, invalid state transition
422  Unprocessable Entity — schema validation failure (FastAPI default)
500  Internal Server Error
```

---

## 10. Auth Approach

### Flow

1. Client sends `phone_number` to `POST /auth/otp/request`.
2. Server generates a 6-digit OTP, hashes it (bcrypt, cost 10), stores in `otp_verifications` with a 10-minute TTL. In dev/mock mode, OTP is always `123456`; no SMS sent.
3. In production, OTP is dispatched via an SMS provider (e.g., Twilio). The provider call is wrapped behind a thin `SmsService` interface so the provider can be swapped without touching auth logic.
4. Client submits `{ phone_number, otp }` to `POST /auth/otp/verify`.
5. Server validates hash, checks TTL, marks OTP as used. Creates user if first login. Issues access token (JWT, 15-minute expiry) and refresh token (opaque UUID, stored hashed in `refresh_tokens`, 30-day expiry).
6. Client stores both tokens. Access token in memory (Riverpod state). Refresh token in secure storage (flutter_secure_storage).
7. Dio interceptor catches 401 on any request, silently calls `POST /auth/token/refresh`, retries the original request once.
8. On logout, client calls `POST /auth/logout`, server revokes the refresh token (sets `revoked_at`). Client clears tokens from memory and secure storage.

### JWT Payload

```json
{
  "sub": "<user_id>",
  "iat": 1234567890,
  "exp": 1234568790,
  "type": "access"
}
```

No roles or permissions in JWT for MVP. Permission checks are hardcoded in service layer (e.g., `if match.tournament.organiser_id != current_user.id: raise ForbiddenError`).

### Security Rules

- OTP attempts are rate-limited: max 5 failed attempts per phone number per 10-minute window. On breach, the OTP record is invalidated and a new request must be made. This is enforced in application logic using a simple counter in the `otp_verifications` table.
- Refresh tokens are single-use: each refresh call issues a new refresh token and revokes the old one (token rotation).
- All tokens over HTTPS only in production.

---

## 11. Offline Score Sync Approach

### Problem
Players may be in venues with poor connectivity when submitting match scores.

### Decision: Optimistic Local Queue

- Score submissions are written to a local Hive queue immediately, giving the user instant feedback ("Score saved locally").
- A background connectivity listener (using `connectivity_plus`) drains the queue when the device comes online.
- Queue entries contain: `{ match_id, sets: [...], submitted_at_local: ISO8601, idempotency_key: UUID }`.
- The server API for score submission accepts an `Idempotency-Key` header. If the same key is seen twice (e.g., retry), the server returns the original response without re-processing.
- Idempotency keys are stored in a server-side table `idempotency_records (key TEXT PK, response_body JSONB, created_at TIMESTAMPTZ)` with a 24-hour TTL (cleaned up by a nightly task or on-demand).
- If the server returns a conflict (e.g., score already submitted by someone else), the queue entry is removed and the user is shown an error alert on next app open.
- Only score submissions are queued offline. All other mutations (create tournament, register, etc.) require connectivity and show an appropriate error if offline.
- The offline queue processes entries sequentially (FIFO), not in parallel, to avoid out-of-order submissions.

### Queue Schema (Hive, local)

```
{
  idempotency_key: String,
  match_id: String,
  sets: List<{ set_number, side_a_score, side_b_score }>,
  submitted_at_local: String (ISO8601),
  retry_count: int,
  last_error: String?
}
```

Max retry count: 5. After 5 failures, the entry is flagged as `dead` and shown to the user in a sync error screen.

---

## 12. Tournament Generation Approach

### Knockout (Single Elimination)

**Input:** Ordered list of participant IDs (seed order set by organiser; random if not set).

**Algorithm:**
1. Determine the smallest power of 2 ≥ number of participants. This is the bracket size (e.g., 12 participants → bracket size 16, meaning 4 byes).
2. Distribute participants into slots 1 through N in seed order.
3. Fill remaining slots with `BYE` markers (from the bottom of the bracket, i.e., high-numbered slots first so that top seeds receive byes).
4. Generate matches for Round 1: slot 1 vs slot N, slot 2 vs slot N-1, ... (standard bracket pairing).
5. Generate subsequent round matches as empty shells with `next_match_id` links forming the bracket tree. Winners auto-advance when one side is BYE.
6. All matches are created in a single database transaction.
7. BYE matches are immediately set to status `BYE` and the present participant is set as `winner_participant_id`.

**Match numbering:**
- Round 1, Match 1 through Match N/2.
- Round 2, Match 1 through Match N/4.
- Final: Round log2(N), Match 1.

**Idempotency:** Bracket generation is only allowed once (`bracket_generated = TRUE` after first generation). Organiser must cancel and recreate the tournament to change the bracket — not supported in MVP.

---

### Round Robin

**Input:** List of participant IDs (order does not affect scheduling, only display labelling).

**Algorithm:**
- Use the standard **Circle Method** (round-robin scheduling algorithm) for N participants.
- If N is odd, add a virtual `BYE` participant to make it even.
- Total rounds = N - 1 (or N if odd, since virtual bye becomes one player's rest round).
- Matches per round = N / 2 (floor).
- Generate all (N*(N-1)/2) match shells in a single transaction.
- Each match gets `round` and `match_number` populated.

**Standings logic (computed, not stored):**
- Win = 2 points, Loss = 0, Walkover win = 2 points.
- Standings are computed at query time from `matches` table, not pre-materialized.
- In case of equal points, players share the rank. No tiebreaker in MVP.

---

## 13. Business Rules

### Tournament

- Only the organiser can change tournament status, edit details, or adjust bracket.
- A user cannot register for a tournament they organise.
- A user cannot register for the same tournament twice.
- For doubles, both players in a pair must have an account. The registering player specifies their partner's `user_id`. The partner does not need to explicitly accept in MVP (honour system).
- Participant withdrawal is allowed only before `IN_PROGRESS`.
- Once `IN_PROGRESS`, only the organiser can force-withdraw (DISQUALIFIED).
- `max_participants` is enforced at registration time. Attempting to register when full returns 409.
- Registration is blocked after `registration_deadline` regardless of status.

### Scoring

- A match cannot have scores submitted unless its status is `IN_PROGRESS`.
- Score submission auto-transitions match from `PENDING` to `IN_PROGRESS` on first submission.
- A set score is valid if both sides' scores are non-negative integers.
- The server determines the winner based on sets won (majority of sets). Client does not determine winner.
- In knockout, a completed match auto-populates the winner into the next round's match slot.
- In round robin, match completion triggers a standings recalculation (computed at query time).

### Training

- Training logs and goals are visible only to the owner. No public feed in MVP.
- A goal's `current_value` can only be updated by the owner.
- Deleting a training log is a hard delete.

---

## 14. Coding Conventions

### Python / Backend

- All modules follow: `models.py → schemas.py → service.py → router.py`.
- Service functions are `async def`. No sync database calls in async context.
- No business logic in routers. Routers only: parse request, call service, return response.
- No business logic in models. Models are pure SQLAlchemy data classes.
- All service functions take explicit parameters (no god-objects). Avoid passing the full request object into a service.
- Exceptions: raise domain exceptions (`NotFoundError`, `ForbiddenError`, `ConflictError`) from services. Routers have a global exception handler that maps these to HTTP responses.
- Naming: `snake_case` for all Python. `SCREAMING_SNAKE_CASE` for constants and enum values.
- Route functions named: `{verb}_{resource}` e.g. `create_tournament`, `list_participants`, `submit_score`.
- All endpoints have explicit `response_model` and `status_code`.
- Avoid raw SQL strings. Use SQLAlchemy expressions. Exception: complex reporting queries may use `text()` with bound params.

### Dart / Flutter

- `camelCase` for variables and functions, `PascalCase` for classes, `snake_case` for file names.
- All network calls go through a repository class. Providers call repositories, not Dio directly.
- All Riverpod providers are code-generated (`@riverpod` annotation).
- No `BuildContext` passed into providers or repositories.
- All API response models have `.fromJson()` factory and are immutable (use `freezed`).
- Screens are dumb — they read providers and dispatch events. No business logic in screens.
- Widget files: one public widget per file. Private helper widgets can cohabit.
- Error handling: all async provider methods catch exceptions and expose `AsyncError` state. Screens display error widgets, not raw exception messages.
- String constants for route names in `AppRoutes` class.
- No hardcoded colours or font sizes inline — always use theme tokens.

### API Contract

- Request bodies: `snake_case` JSON keys.
- Response bodies: `snake_case` JSON keys.
- IDs always returned as strings (UUID format).
- Timestamps always in ISO 8601 UTC with `Z` suffix.
- Booleans never as `0/1` or `"true"/"false"` strings.
- Enum values as uppercase strings matching the Python enum names.

---

## 15. Testing Priorities

### Backend (pytest + pytest-asyncio)

**Priority 1 — Must have before Phase 1 ship:**
- Auth: OTP request, verify, refresh, logout
- Bracket generation: knockout with N=4, 8, 16, and byes (N=5, 6, 7)
- Bracket generation: round robin with N=4, 5
- Score submission: valid sets, winner determination
- Tournament status transitions: valid and invalid

**Priority 2 — Before Phase 2:**
- Tournament participant registration constraints (full, deadline, duplicate)
- Training log CRUD
- Training goal status transitions
- Discovery list filtering
- Score idempotency

**Priority 3 — Nice to have:**
- Organiser permission enforcement
- Token rotation behaviour
- OTP rate limiting

### Flutter

- Repository unit tests: mock Dio, test JSON parsing
- Provider unit tests: mock repository, test state transitions
- No widget tests in MVP (deprioritised in favour of speed)
- End-to-end manual test checklist per feature before release

### What is NOT tested in MVP

- Performance / load testing
- Penetration testing
- Cross-device UI testing (manual smoke test on one Android + one iOS device)

---

## 16. Phased Implementation Order

### Phase 1 — Foundation (Weeks 1–3)

**Goal:** A working app where a user can register, create a tournament, run a knockout bracket, and submit scores.

**Backend:**
1. Project scaffolding, database setup, Alembic migrations
2. `common` module (dependencies, response envelope, exceptions)
3. `auth` module — OTP flow (mock mode), JWT, refresh, logout
4. `users` module — create/update player profile
5. `tournaments` module — create, list, detail, status transitions
6. `tournaments/bracket/knockout.py` — bracket generation
7. `scores` module — score submission, winner determination
8. Knockout match auto-advancement on score completion

**Flutter:**
1. Project scaffolding, Riverpod, go_router, Dio setup
2. Auth screens (phone entry, OTP entry)
3. Home screen (static shell)
4. Tournament list and detail screens
5. Create tournament screen
6. Knockout bracket screen (read-only tree view)
7. Score submission screen
8. Basic profile screen

**Definition of done for Phase 1:** A real user can sign up, create a knockout tournament, add participants, generate a bracket, submit scores for each match, and see a winner declared.

---

### Phase 2 — Round Robin and Training (Weeks 4–5)

**Goal:** Round robin support, full training log and goals feature.

**Backend:**
1. `tournaments/bracket/round_robin.py` — round robin schedule generation
2. Round robin standings computation endpoint
3. `training` module — logs and goals CRUD
4. Goal `current_value` update and auto-status transition

**Flutter:**
1. Round robin table screen
2. Training log screens (list, add, edit)
3. Goal screens (list, add, edit, progress update)

---

### Phase 3 — Discovery and Polish (Weeks 6–7)

**Goal:** Player and tournament discovery, offline score sync, UX polish.

**Backend:**
1. `discovery` module — player/tournament/venue queries
2. Venue submission
3. Idempotency key support on score submission endpoint
4. OTP rate limiting

**Flutter:**
1. Discovery screen with city filter
2. Public player profile screen
3. Offline score queue (Hive queue + connectivity listener)
4. Sync error screen
5. Loading states, empty states, error states on all screens
6. App icon, splash screen, basic onboarding

---

### Phase 4 — Hardening (Week 8)

**Goal:** Production readiness for soft launch.

1. HTTPS enforcement, CORS hardening
2. Environment config (dev / staging / prod)
3. S3-compatible storage setup for future profile photos
4. Structured logging (structlog) with request ID tracing
5. Alembic migration review — ensure all FK constraints, indexes on frequently queried columns (`tournaments.city`, `tournaments.status`, `matches.tournament_id`, `training_logs.user_id`)
6. Database indexes audit
7. Test suite completion (Priority 1 + Priority 2 items)
8. Manual QA checklist pass on Android and iOS

---

### Deliberately Deferred (Post-MVP)

- Profile photo upload
- Push notifications
- GPS-based nearby discovery
- Doubles partner acceptance flow
- Third-place match in knockout
- Advanced tiebreakers in round robin
- Tournament payment / entry fees
- Match scheduling (date/time assignment per match)
- Chat or messaging between players
- Social feed / activity stream
- Web app
- Admin dashboard
- Analytics / reporting
- Email login
- OAuth (Google, Apple)

---

*End of MVP Build Plan*
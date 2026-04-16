# Badminton Platform — Implementation Roadmap

**Version:** 1.0  
**Date:** April 2026  
**Derived from:** MVP_BUILD_PLAN.md  
**Scope:** Concrete build sequence — no code generated

---

## How to Read This Document

Each phase is a **vertical slice** — backend + Flutter + DB + tests all move together. Phases are sized so that a single implementation session can complete one without losing context. Phases must be completed in order unless explicitly marked as parallelisable.

**Phase gate rule:** Tests marked as **required** must pass before the next phase begins. No exceptions.

**Parallelisation note:** Backend and Flutter within the same phase can be built in parallel once the API contract for that phase is agreed and locked. The contract is defined by this roadmap.

---

## Phase Overview

| # | Name | Builds On | Est. Effort |
|---|---|---|---|
| P0 | Project Scaffolding & Infra | — | 1–2 days |
| P1 | Auth — OTP + JWT | P0 | 2 days |
| P2 | User Profile | P1 | 1–2 days |
| P3 | Tournament Core (CRUD + Lifecycle) | P2 | 2–3 days |
| P4 | Participant Registration | P3 | 1–2 days |
| P5 | Knockout Bracket Generation | P4 | 2 days |
| P6 | Score Submission + Match Advancement | P5 | 2 days |
| P7 | Round Robin Generation + Standings | P4 | 2 days |
| P8 | Training Logs | P2 | 1–2 days |
| P9 | Training Goals | P8 | 1 day |
| P10 | Discovery — Players, Tournaments, Venues | P2, P3 | 1–2 days |
| P11 | Offline Score Sync | P6 | 1–2 days |
| P12 | OTP Hardening + Score Idempotency | P1, P6 | 1 day |
| P13 | Production Hardening | All prior | 2–3 days |

Total: ~8 working weeks (2 engineers) or 5–6 weeks (focused solo sprint)

---

## P0 — Project Scaffolding & Infra

### Goal
Empty but runnable projects on both sides. CI passes. Database connects. No features yet.

### Backend Scope
- Create `backend/` repo with `main.py`, `config.py`, `database.py`
- Pydantic `BaseSettings` reading from `.env`
- Async SQLAlchemy engine + session factory
- Alembic initialised, `env.py` wired to async engine
- `common/` module: `exceptions.py`, `response.py`, `pagination.py`, `enums.py`, `dependencies.py` (stubs only for `get_db`, `get_current_user`)
- Health check endpoint: `GET /api/v1/health` → `{ "status": "ok" }`
- structlog configured for JSON output
- CORS configured (allow all origins in dev)
- `requirements.txt` (or `pyproject.toml`) with pinned deps: fastapi, uvicorn, sqlalchemy, alembic, pydantic-settings, python-jose, passlib, structlog, asyncpg, pytest, pytest-asyncio, httpx

### Flutter Scope
- Create Flutter project targeting Android + iOS
- Add dependencies to `pubspec.yaml`: riverpod, riverpod_generator, go_router, dio, hive, hive_flutter, flutter_secure_storage, reactive_forms, freezed, json_serializable, connectivity_plus, build_runner
- `core/theme/` — `AppTheme`, `AppColors` (Material 3 seed colour configured)
- `core/network/dio_client.dart` — Dio instance, base URL from env/config, empty interceptor stubs
- `core/router/app_router.dart` — go_router with a single placeholder `/` route
- `main.dart` + `app.dart` — `ProviderScope` wrapping `MaterialApp.router`
- App builds and launches to a blank scaffold on Android and iOS

### DB / Migration Scope
- No tables yet
- Confirm Alembic can connect and run `alembic upgrade head` with no migrations (no-op)
- Docker Compose file: `postgres:15`, `backend` service — for local dev

### Tests Required
- `GET /api/v1/health` returns 200 ✓
- `alembic upgrade head` runs without error ✓
- Flutter `flutter test` passes (0 tests, no failures) ✓

### Done Criteria
- [ ] Backend starts with `uvicorn main:app --reload` with no errors
- [ ] Flutter app builds on Android and iOS with no errors
- [ ] Health endpoint returns `{"data": {"status": "ok"}, "error": null, "meta": {}}`
- [ ] `alembic upgrade head` runs cleanly against a fresh Postgres instance
- [ ] Docker Compose brings up Postgres + backend together

### Risks
- asyncpg / SQLAlchemy async driver version conflicts — resolve at this phase, not later
- Flutter build toolchain setup time (especially iOS signing) can consume a day

### Out of Scope for P0
- Any auth, user, or feature logic
- Any real database tables
- Any Flutter screens beyond the blank shell

---

## P1 — Auth: OTP + JWT

### Goal
A user can request an OTP, verify it, receive tokens, refresh the access token, and log out. No SMS in dev (mock mode). Flutter has working auth flow screens connected to the real API.

### Depends On
P0 (scaffolding complete, DB connection working)

### Backend Scope
- `auth/models.py` — `OtpVerification`, `RefreshToken` SQLAlchemy models
- `auth/schemas.py` — request/response Pydantic models for all 4 auth endpoints
- `auth/service.py`:
  - `request_otp(phone_number)` — generate OTP, hash (bcrypt), store, return mock OTP in dev
  - `verify_otp(phone_number, otp)` — validate hash + TTL, mark used, create user if new, issue token pair
  - `refresh_token(refresh_token_str)` — validate, rotate, issue new pair
  - `logout(refresh_token_str)` — revoke token (set `revoked_at`)
- `auth/router.py` — 4 routes wired up
- `common/dependencies.py` — `get_current_user` fully implemented (decode JWT, load user, raise 401 on failure)
- `users/models.py` — `User` model only (no profile yet); needed by auth service to create users on first OTP verify
- JWT secret + expiry configurable via `.env`
- Mock mode: if `OTP_MOCK_MODE=true` in env, skip hash check and accept `123456`

### Flutter Scope
- `core/storage/prefs.dart` — thin wrapper for `SharedPreferences` (store `is_logged_in` flag)
- `core/storage/secure_storage.dart` — flutter_secure_storage wrapper for `refresh_token`
- `core/network/auth_interceptor.dart` — Dio interceptor: attach Bearer token, catch 401, call refresh, retry once, logout on refresh failure
- `features/auth/data/auth_repository.dart` — calls all 4 auth endpoints
- `features/auth/providers/auth_provider.dart` — holds `accessToken` in memory, `isLoggedIn` state
- `features/auth/screens/phone_entry_screen.dart` — phone number input, request OTP button
- `features/auth/screens/otp_screen.dart` — 6-digit OTP input, verify button, resend
- `core/router/app_router.dart` — route guard: redirect to `/login` if not logged in
- On successful login → navigate to `/home` (placeholder home screen)
- On logout → clear tokens, redirect to `/login`

### DB / Migration Scope
- Migration 001: create `users` table
- Migration 002: create `otp_verifications` table
- Migration 003: create `refresh_tokens` table

### Tests Required (gate — must pass before P2)
- `test_auth.py`:
  - `POST /auth/otp/request` — returns 200, OTP created in DB ✓
  - `POST /auth/otp/verify` — correct OTP returns token pair ✓
  - `POST /auth/otp/verify` — wrong OTP returns 401 ✓
  - `POST /auth/otp/verify` — expired OTP returns 401 ✓
  - `POST /auth/otp/verify` — used OTP returns 401 ✓
  - `POST /auth/token/refresh` — valid refresh token returns new pair, old token revoked ✓
  - `POST /auth/token/refresh` — revoked refresh token returns 401 ✓
  - `POST /auth/logout` — refresh token is revoked ✓
  - `GET /api/v1/health` with valid Bearer token — `get_current_user` resolves correctly ✓
  - `GET /api/v1/health` with no token — returns 401 ✓

### Done Criteria
- [ ] All 10 auth test cases pass
- [ ] Flutter: phone entry → OTP entry → home (placeholder) flows end-to-end on device
- [ ] Flutter: token auto-refresh works (manually expire a token, next API call triggers refresh transparently)
- [ ] Flutter: logout clears tokens and redirects to login
- [ ] Mock mode (`OTP_MOCK_MODE=true`) accepts `123456` for any number

### Risks
- JWT library choice (`python-jose` vs `PyJWT`) — pick one at P0, do not change
- bcrypt hashing OTP adds ~200ms per request; acceptable for MVP, note it
- flutter_secure_storage requires platform-specific Keychain / Keystore config — test on real device, not just emulator

### Out of Scope for P1
- Player profile (P2)
- OTP rate limiting (P12)
- SMS provider integration (post-MVP)
- Token rotation edge cases beyond the happy path and one revoked-token test

---

## P2 — User Profile

### Goal
After login, a user can view and edit their player profile (display name, city, skill level, play style, bio). Other users' public profiles are viewable.

### Depends On
P1 (auth working, `get_current_user` available)

### Backend Scope
- `users/models.py` — add `PlayerProfile` SQLAlchemy model (alongside existing `User`)
- `users/schemas.py` — `PlayerProfileCreate`, `PlayerProfileUpdate`, `PlayerProfileResponse`, `UserWithProfileResponse`
- `users/service.py`:
  - `get_my_profile(user_id)` — load user + profile, create empty profile if not exists
  - `upsert_profile(user_id, data)` — create or update profile
  - `get_public_profile(user_id)` — load profile; raise 404 if user not found
- `users/router.py`:
  - `GET /api/v1/users/me` — own user + profile
  - `PUT /api/v1/users/me/profile` — upsert profile
  - `GET /api/v1/users/{user_id}/profile` — public profile

### Flutter Scope
- `features/profile/data/profile_repository.dart`
- `features/profile/providers/profile_provider.dart` — own profile state, public profile family provider
- `features/profile/screens/my_profile_screen.dart` — display own profile, edit button
- `features/profile/screens/edit_profile_screen.dart` — reactive form: display_name (required), city, skill_level (dropdown), play_style (dropdown), bio (multiline)
- `features/profile/screens/player_profile_screen.dart` — read-only public profile for another user
- `core/widgets/avatar_widget.dart` — text-initials avatar (no photo in MVP)
- `home_screen.dart` — add "My Profile" navigation entry

### DB / Migration Scope
- Migration 004: create `player_profiles` table with FK to `users`

### Tests Required (gate — must pass before P3)
- `test_users.py`:
  - `GET /users/me` — returns user + empty profile on first login ✓
  - `PUT /users/me/profile` — creates profile ✓
  - `PUT /users/me/profile` — updates existing profile ✓
  - `GET /users/{id}/profile` — returns profile for another user ✓
  - `GET /users/{id}/profile` — returns 404 for unknown user ✓
  - All 3 endpoints return 401 without auth ✓

### Done Criteria
- [ ] All 6 profile test cases pass
- [ ] Flutter: full edit-profile flow works on device
- [ ] Flutter: navigating to another user's profile (by UUID, manually) shows their public profile
- [ ] Avatar shows initials from display_name

### Risks
- Profile might not exist for new users — `get_my_profile` must not 404; must return empty-ish profile gracefully
- `skill_level` and `play_style` enums: agree on exact string values in `common/enums.py` before P2 starts, as Flutter and backend must match

### Out of Scope for P2
- Profile photo upload
- Showing profiles in any list (discovery is P10)

---

## P3 — Tournament Core (CRUD + Lifecycle)

### Goal
An organiser can create a tournament, edit its details, view it, and transition it through status states (DRAFT → REGISTRATION_OPEN → REGISTRATION_CLOSED → IN_PROGRESS → COMPLETED / CANCELLED). Other users can list and view tournaments.

### Depends On
P2 (user profile done; organiser identity needed)

### Backend Scope
- `tournaments/models.py` — `Tournament` model only (no matches/participants yet)
- `tournaments/schemas.py` — `TournamentCreate`, `TournamentUpdate`, `TournamentResponse`, `TournamentStatusTransitionRequest`
- `tournaments/service.py`:
  - `create_tournament(organiser_id, data)` — creates in DRAFT status
  - `get_tournament(tournament_id)` — detail; raise 404 if not found or deleted
  - `list_tournaments(city, status, format, page, page_size)` — paginated
  - `update_tournament(tournament_id, organiser_id, data)` — only if DRAFT or REGISTRATION_OPEN; raise 403 if not organiser
  - `transition_status(tournament_id, organiser_id, next_status)` — validates allowed transitions, applies; raise 409 on invalid
  - `cancel_tournament(tournament_id, organiser_id)` — soft delete; sets status CANCELLED and `deleted_at`
- `tournaments/router.py`:
  - `POST /api/v1/tournaments`
  - `GET /api/v1/tournaments`
  - `GET /api/v1/tournaments/{id}`
  - `PUT /api/v1/tournaments/{id}`
  - `DELETE /api/v1/tournaments/{id}`
  - `POST /api/v1/tournaments/{id}/status`

### Flutter Scope
- `features/tournaments/data/tournament_repository.dart`
- `features/tournaments/providers/tournament_provider.dart` — list provider, detail provider
- `features/tournaments/screens/tournament_list_screen.dart` — paginated list, city/status filter chips
- `features/tournaments/screens/tournament_detail_screen.dart` — detail view, status badge, edit/status-transition buttons (visible to organiser only)
- `features/tournaments/screens/create_tournament_screen.dart` — reactive form: title, description, city, format (KNOCKOUT/ROUND_ROBIN), match_format (BO1/3/5), play_type, max_participants, registration_deadline, starts_at
- `features/tournaments/screens/edit_tournament_screen.dart` — same form pre-filled
- `home_screen.dart` — "My Tournaments" section (tournaments where user is organiser)

### DB / Migration Scope
- Migration 005: create `tournaments` table

### Tests Required (gate — must pass before P4)
- `test_tournaments.py`:
  - `POST /tournaments` — creates in DRAFT ✓
  - `GET /tournaments/{id}` — returns detail ✓
  - `GET /tournaments/{id}` — 404 on unknown ✓
  - `GET /tournaments` — lists all (no filter) ✓
  - `GET /tournaments?city=Chennai` — filters by city ✓
  - `GET /tournaments?status=REGISTRATION_OPEN` — filters by status ✓
  - `PUT /tournaments/{id}` — organiser can update in DRAFT ✓
  - `PUT /tournaments/{id}` — non-organiser gets 403 ✓
  - `PUT /tournaments/{id}` — cannot update IN_PROGRESS tournament ✓
  - `POST /tournaments/{id}/status` — DRAFT → REGISTRATION_OPEN ✓
  - `POST /tournaments/{id}/status` — invalid transition (e.g., DRAFT → COMPLETED) returns 409 ✓
  - `DELETE /tournaments/{id}` — soft deletes, subsequent GET returns 404 ✓

### Done Criteria
- [ ] All 12 tournament core test cases pass
- [ ] Flutter: create → view → edit → status transition flow works on device
- [ ] Deleted tournaments do not appear in list
- [ ] Only organiser sees edit/delete/transition controls

### Risks
- Status transition table (allowed transitions) must be implemented as an explicit map, not a chain of if/else — easier to test and extend
- `registration_deadline` and `starts_at` timezone handling: always store and return UTC; Flutter displays in local time using device timezone

### Out of Scope for P3
- Participants (P4)
- Bracket (P5, P7)
- Scores (P6)

---

## P4 — Participant Registration

### Goal
Users can register for a tournament (singles or doubles with a partner). Organisers can view the participant list and set seed order. Users can withdraw. Constraints (full, deadline, duplicate, self-registration) are enforced.

### Depends On
P3 (tournaments exist)

### Backend Scope
- `tournaments/models.py` — add `TournamentParticipant` model
- `tournaments/schemas.py` — add `ParticipantRegisterRequest`, `ParticipantResponse`, `SeedOrderRequest`
- `tournaments/service.py` — add:
  - `register_participant(tournament_id, user_id, partner_user_id?)`:
    - Raise 403 if user is the organiser
    - Raise 409 if already registered
    - Raise 409 if tournament is not REGISTRATION_OPEN
    - Raise 409 if past `registration_deadline`
    - Raise 409 if at `max_participants` capacity
    - For doubles: validate partner exists; raise 409 if partner already registered
  - `list_participants(tournament_id)` — ordered by `seed_order` nulls last, then `registered_at`
  - `withdraw_participant(tournament_id, user_id)` — only if tournament is not IN_PROGRESS/COMPLETED
  - `set_seed_order(tournament_id, organiser_id, ordered_participant_ids)` — validate all IDs belong to this tournament; update `seed_order` values
- `tournaments/router.py` — add:
  - `POST /api/v1/tournaments/{id}/participants`
  - `GET /api/v1/tournaments/{id}/participants`
  - `DELETE /api/v1/tournaments/{id}/participants/{participant_id}`
  - `PUT /api/v1/tournaments/{id}/participants/seed-order`

### Flutter Scope
- `features/tournaments/screens/tournament_detail_screen.dart` — add participant list section, "Register" button (if REGISTRATION_OPEN and not yet registered), "Withdraw" button (if registered)
- `features/tournaments/screens/participants_screen.dart` — full participant list with drag-to-reorder seed order (organiser only)
- `features/tournaments/screens/register_dialog.dart` — doubles: search/select partner by display name or phone; singles: one-tap confirm

### DB / Migration Scope
- Migration 006: create `tournament_participants` table with FK to `tournaments` and `users`; unique constraint on `(tournament_id, user_id)`

### Tests Required (gate — must pass before P5 and P7)
- `test_participants.py`:
  - Register self (singles) for open tournament → 201 ✓
  - Register again → 409 (duplicate) ✓
  - Register for own tournament → 403 ✓
  - Register for DRAFT tournament → 409 ✓
  - Register past deadline → 409 ✓
  - Register when full (at max_participants) → 409 ✓
  - Register doubles with valid partner → 201, partner also appears in list ✓
  - Register doubles with partner already in tournament → 409 ✓
  - Withdraw own registration → 200 ✓
  - Withdraw when tournament is IN_PROGRESS → 409 ✓
  - Set seed order (organiser) → 200, list returned in new order ✓
  - Set seed order (non-organiser) → 403 ✓
  - `GET /participants` returns paginated list ✓

### Done Criteria
- [ ] All 13 participant test cases pass
- [ ] Flutter: register/withdraw flow works on device
- [ ] Organiser can drag-reorder participants; order is persisted
- [ ] Participant count shown on tournament detail screen

### Risks
- Doubles registration means one registration row per pair (not per player). Decide: does `user_id` = registering player and `partner_user_id` = their partner? Yes — this is the established schema. Enforce that only the registering player can withdraw (not the partner).
- Drag-to-reorder on Flutter: use `ReorderableListView`, not a third-party lib

### Out of Scope for P4
- Bracket generation (P5, P7)
- Disqualification (P6, organiser action during match)

---

## P5 — Knockout Bracket Generation

### Goal
An organiser can generate a single-elimination bracket for a tournament with 4–64 participants. The bracket is created in one transaction. Byes are handled automatically. The bracket is viewable as a tree.

### Depends On
P4 (participants exist and seed order can be set)

### Backend Scope
- `tournaments/models.py` — add `Match` model (no `MatchScore` yet)
- `tournaments/schemas.py` — add `MatchResponse`, `BracketResponse` (tree structure)
- `tournaments/bracket/knockout.py` — pure bracket generation logic:
  - `generate_knockout_bracket(participants: list[UUID]) -> list[MatchCreate]`
  - Input: ordered list of participant IDs (seeded)
  - Output: flat list of match definitions with round, match_number, side_a, side_b, next_match_id, status
  - Algorithm: power-of-2 expansion, bye assignment from bottom slots, standard bracket pairing (1 vs N, 2 vs N-1…)
  - BYE matches: status = BYE, `winner_participant_id` set immediately
- `tournaments/service.py` — add:
  - `generate_bracket(tournament_id, organiser_id)`:
    - Raise 403 if not organiser
    - Raise 409 if `bracket_generated = TRUE`
    - Raise 409 if participant count < 4
    - Raise 409 if tournament status ≠ REGISTRATION_CLOSED
    - Call `knockout.generate_knockout_bracket()`
    - Insert all matches in one DB transaction
    - Set `bracket_generated = TRUE`, transition status to IN_PROGRESS
  - `get_bracket(tournament_id)` — load all matches, return as structured tree
  - `list_matches(tournament_id)` — flat match list
- `tournaments/router.py` — add:
  - `POST /api/v1/tournaments/{id}/bracket/generate`
  - `GET /api/v1/tournaments/{id}/bracket`
  - `GET /api/v1/tournaments/{id}/matches`

### Flutter Scope
- `features/bracket/screens/knockout_bracket_screen.dart` — horizontal scrollable bracket tree; each node shows participant names (or "BYE"), scores (empty until submitted), and status badge
- `features/tournaments/screens/tournament_detail_screen.dart` — add "Generate Bracket" button (organiser only, when REGISTRATION_CLOSED and bracket not yet generated); navigate to bracket screen
- Bracket tree widget: render rounds as columns, matches as cards, connecting lines between parent/child matches

### DB / Migration Scope
- Migration 007: create `matches` table with self-referential `next_match_id` FK

### Tests Required (gate — must pass before P6)
- `test_bracket_knockout.py`:
  - Generate bracket with exactly 4 participants → 4 matches (2 R1 + 1 R2 final + wait, for N=4 power-of-2=4, 0 byes → 2 R1 matches, 1 final = 3 matches) ✓
  - Generate bracket with 8 participants → 7 matches, 0 byes ✓
  - Generate bracket with 5 participants → power-of-2=8, 3 byes; verify bye matches have status=BYE and winner set ✓
  - Generate bracket with 6 participants → 2 byes ✓
  - Generate bracket with 16 participants → 15 matches ✓
  - Generate bracket twice → second call returns 409 ✓
  - Generate with < 4 participants → 409 ✓
  - Generate with status ≠ REGISTRATION_CLOSED → 409 ✓
  - Non-organiser calls generate → 403 ✓
  - `GET /bracket` returns correct tree structure (next_match_id links correct) ✓
  - Bye winner auto-populated in parent match's side slot ✓

### Done Criteria
- [ ] All 11 knockout bracket test cases pass
- [ ] Flutter: bracket tree renders correctly for N=4, N=5, N=8
- [ ] BYE nodes shown distinctly (greyed out label)
- [ ] Completed matches show winner highlight

### Risks
- `next_match_id` assignment logic for odd-sized brackets is the trickiest part of the algorithm — test all N values 4–8 manually
- Flutter bracket tree widget is a custom layout (no off-the-shelf widget does this well) — allocate extra time; a horizontal `ListView` of `Column`s with custom `CustomPainter` lines is the pragmatic approach

### Out of Scope for P5
- Score submission (P6)
- Match auto-advancement (P6)
- Round robin (P7)

---

## P6 — Score Submission + Match Advancement

### Goal
A participant or organiser can submit set scores for a match. The system determines the winner, marks the match COMPLETED, and auto-advances the winner to the next match in the knockout bracket. Organiser can correct scores.

### Depends On
P5 (matches exist in DB)

### Backend Scope
- `tournaments/models.py` — add `MatchScore` model
- `scores/schemas.py` — `ScoreSubmitRequest` (list of sets), `ScoreResponse`
- `scores/service.py`:
  - `submit_score(match_id, submitter_id, sets)`:
    - Load match; raise 404 if not found
    - Raise 409 if match status is BYE, WALKOVER, or COMPLETED (unless submitter is organiser — then allow correction)
    - Validate sets: count must match `match_format` (BO1=1 set, BO3=up to 3, BO5=up to 5); each score non-negative integer
    - Auto-transition match to IN_PROGRESS if PENDING
    - Delete existing `match_scores` for this match (replace semantics — last write wins)
    - Insert new `match_scores` rows (one per set)
    - Determine winner: count sets won by each side; side with majority wins
    - If winner determined:
      - Set `match.winner_participant_id`
      - Set `match.status = COMPLETED`, `match.completed_at = now()`
      - If `match.next_match_id` exists: assign winner to the appropriate side slot in the next match (side_a if first available, side_b if side_a filled)
      - Check if this was the final match: if so, set `tournament.status = COMPLETED`
  - `update_score(match_id, organiser_id, sets)` — organiser correction; same logic but only organiser can call
- `scores/router.py`:
  - `POST /api/v1/matches/{id}/scores`
  - `PUT /api/v1/matches/{id}/scores`
- `matches` read endpoints (reuse from P5 `GET /matches/{id}`)
- `PUT /api/v1/matches/{id}/status` — organiser can set WALKOVER; set winner to present participant

### Flutter Scope
- `features/matches/data/match_repository.dart`
- `features/matches/providers/match_provider.dart`
- `features/matches/screens/match_detail_screen.dart` — participants, current scores by set, match status, "Submit Score" button (if eligible), "Correct Score" button (organiser only)
- `features/matches/screens/score_submit_screen.dart` — dynamic set rows (BO1: 1 row, BO3: up to 3 rows, BO5: up to 5 rows); each row is two number fields (side A score, side B score); submit button
- `features/bracket/screens/knockout_bracket_screen.dart` — tap on a match card to navigate to match detail

### DB / Migration Scope
- Migration 008: create `match_scores` table with FK to `matches` and `users`

### Tests Required (gate — must pass before P11 and P12)
- `test_scores.py`:
  - Submit valid BO1 score → match COMPLETED, winner set ✓
  - Submit valid BO3 score (2 sets, clear winner) → COMPLETED ✓
  - Submit BO3 where all 3 sets needed (1-1 after 2) → winner from set 3 ✓
  - Submit score for BYE match → 409 ✓
  - Submit score for COMPLETED match by non-organiser → 409 ✓
  - Organiser corrects score of COMPLETED match → 200, new winner set ✓
  - Winner auto-placed in next match's side slot ✓
  - Both sides of next match filled → next match transitions from PENDING to ready (side_a and side_b both non-null) ✓
  - Final match completion → tournament status COMPLETED ✓
  - Non-participant, non-organiser submits score → 403 ✓
  - Invalid score (negative number) → 422 ✓
  - Walkover: organiser sets match to WALKOVER → winner is present participant ✓

### Done Criteria
- [ ] All 12 score test cases pass
- [ ] Flutter: full knockout tournament can be played to completion end-to-end on device (create → register 4 players → close registration → generate bracket → submit scores → final match completes → tournament marked COMPLETED)
- [ ] Winner propagation visible in bracket screen without manual refresh (provider invalidated on score submit)

### Risks
- "Which side does the winner go into in the next match?" — needs a clear rule: whichever slot (`side_a` or `side_b`) in `next_match_id` was pre-assigned at bracket generation time. Bracket generator must stamp each match with the `side` the winner feeds into. Add `winner_feeds_side: A | B` field to match, set at generation time.
- Score correction by organiser is replace-all semantics — make this explicit in the API and UI

### Out of Scope for P6
- Round robin standings (P7)
- Offline sync (P11)
- Idempotency keys (P12)

---

## P7 — Round Robin Generation + Standings

### Goal
An organiser can generate a round robin schedule. All participants play each other once. Standings are computed live. Flutter shows a standings table and match list by round.

### Depends On
P4 (participants), P5 infra (Match model exists)

> **Note:** P7 is independent of P5/P6 and can be built in parallel with P6 by a second developer. P7 reuses the `Match` model from P5's migration.

### Backend Scope
- `tournaments/bracket/round_robin.py` — pure schedule generation:
  - `generate_round_robin_schedule(participants: list[UUID]) -> list[MatchCreate]`
  - Circle method: if N is odd, add a virtual BYE entry; N-1 rounds (or N if odd), each round has N//2 real matches
  - No `next_match_id` for round robin (NULL for all)
  - All matches created with status PENDING
- `tournaments/service.py` — add:
  - `generate_bracket(tournament_id, organiser_id)` — modified to branch on `tournament.format`; calls `knockout.generate_knockout_bracket` or `round_robin.generate_round_robin_schedule`
  - `get_round_robin_standings(tournament_id)` — compute from matches at query time:
    - Win = 2 pts, Loss = 0 pts, Walkover win = 2 pts
    - Return list of `{participant, matches_played, wins, losses, points}` sorted by points desc
- `tournaments/router.py` — add:
  - `GET /api/v1/tournaments/{id}/standings` — returns standings list (for round robin; 404 for knockout)

Score submission for round robin matches reuses P6's `scores/service.py` exactly — no special-casing needed (no `next_match_id` to advance).

### Flutter Scope
- `features/bracket/screens/round_robin_table_screen.dart` — two tabs: "Standings" (table: rank, player, played, W, L, pts) and "Matches" (matches grouped by round, each tappable to navigate to match detail)
- `features/tournaments/screens/tournament_detail_screen.dart` — navigate to correct bracket screen based on `tournament.format`

### DB / Migration Scope
- No new migrations (reuses Migration 007's `matches` table)

### Tests Required (gate — must pass before P13)
- `test_bracket_round_robin.py`:
  - Generate RR schedule with 4 participants → 6 matches (4 choose 2), 3 rounds ✓
  - Generate RR schedule with 5 participants → 10 matches, 5 rounds (virtual bye) ✓
  - Generate RR schedule with 3 participants → 409 (< 4 minimum) ✓
  - `GET /standings` after 0 matches → all at 0 pts ✓
  - `GET /standings` after some matches → correct points ✓
  - Tied points → both players share rank (no tiebreaker) ✓
  - Score submission for RR match works (reuses P6 tests, just verify no next_match advancement runs) ✓

### Done Criteria
- [ ] All 7 round robin test cases pass
- [ ] Flutter: full round robin tournament playable end-to-end: create RR → register 4 players → close → generate → submit all match scores → standings update correctly
- [ ] Standings table updates on return from match detail screen

### Risks
- Circle method off-by-one in round count for even vs odd N — test both carefully
- Standings computed at query time may be slow for large N; for MVP (max 16 players = max 120 matches) this is fine — note for future caching

### Out of Scope for P7
- Tiebreaker beyond points
- Third-place match

---

## P8 — Training Logs

### Goal
A user can log training sessions (date, duration, session type, notes), view their log history, and delete entries.

### Depends On
P2 (user profile done; `get_current_user` available)

> **Note:** P8 is fully independent of P3–P7 and can be built in parallel with any of those phases.

### Backend Scope
- `training/models.py` — `TrainingLog` SQLAlchemy model
- `training/schemas.py` — `TrainingLogCreate`, `TrainingLogUpdate`, `TrainingLogResponse`
- `training/service.py`:
  - `create_log(user_id, data)` — create entry
  - `list_logs(user_id, date_from?, date_to?, session_type?, page, page_size)` — own logs only, paginated
  - `get_log(log_id, user_id)` — raise 404 or 403 if not owner
  - `update_log(log_id, user_id, data)` — raise 403 if not owner
  - `delete_log(log_id, user_id)` — hard delete; raise 403 if not owner
- `training/router.py` — 5 routes: POST, GET (list), GET (detail), PUT, DELETE

### Flutter Scope
- `features/training/data/training_repository.dart`
- `features/training/providers/training_provider.dart`
- `features/training/screens/training_log_screen.dart` — paginated list of logs (date, session type, duration), FAB to add
- `features/training/screens/add_log_screen.dart` — date picker, duration (minutes), session type (dropdown: PRACTICE/FITNESS/MATCH/DRILL/REST), notes text area
- `features/training/screens/log_detail_screen.dart` — view + edit + delete

### DB / Migration Scope
- Migration 009: create `training_logs` table

### Tests Required
- `test_training_logs.py`:
  - Create log → 201 ✓
  - List logs — only own entries returned ✓
  - Filter by session_type → correct subset ✓
  - Filter by date range → correct subset ✓
  - Get own log detail → 200 ✓
  - Get another user's log → 403 ✓
  - Update own log → 200 ✓
  - Delete own log → 200, subsequent GET → 404 ✓

### Done Criteria
- [ ] All 8 training log test cases pass
- [ ] Flutter: create/edit/delete log flow works on device
- [ ] Date range filter chip works on list screen

### Risks
- `logged_at` is a `DATE` (not datetime) — Flutter date picker must strip time before sending
- Session types must match exactly between Flutter dropdown and backend enum

### Out of Scope for P8
- Training goals (P9)
- Any social/sharing of logs

---

## P9 — Training Goals

### Goal
A user can set a training goal (title, metric, target, deadline), manually update progress, and mark it achieved or abandoned. Goal status auto-transitions to ACHIEVED when `current_value >= target_value`.

### Depends On
P8 (training module scaffolding exists)

### Backend Scope
- `training/models.py` — add `TrainingGoal` model
- `training/schemas.py` — add `GoalCreate`, `GoalUpdate`, `GoalResponse`
- `training/service.py` — add:
  - `create_goal(user_id, data)` — status defaults to ACTIVE
  - `list_goals(user_id, status?)` — own goals only
  - `update_goal(goal_id, user_id, data)`:
    - Raise 403 if not owner
    - If `current_value >= target_value` after update → auto-set status to ACHIEVED
  - `delete_goal(goal_id, user_id)` — hard delete
- `training/router.py` — add 4 routes: POST, GET (list), PUT, DELETE

### Flutter Scope
- `features/training/screens/goals_screen.dart` — list of goals with progress bar, status filter tabs (ALL / ACTIVE / ACHIEVED / ABANDONED), FAB to add
- `features/training/screens/add_goal_screen.dart` — title, metric (free text), target_value (number), deadline (date picker)
- Inline progress update on goal card: `+` button to increment current_value, or edit to set exact value
- Achieved goals shown with a distinct colour/icon

### DB / Migration Scope
- Migration 010: create `training_goals` table

### Tests Required
- `test_training_goals.py`:
  - Create goal → ACTIVE ✓
  - Update current_value below target → still ACTIVE ✓
  - Update current_value to equal target → auto ACHIEVED ✓
  - Update current_value above target → ACHIEVED ✓
  - Manually set status to ABANDONED → accepted ✓
  - Set ABANDONED goal back to ACTIVE → accepted ✓
  - List goals filtered by status ✓
  - Non-owner update → 403 ✓

### Done Criteria
- [ ] All 8 goal test cases pass
- [ ] Flutter: goal creation, progress update, achieved state all visible on device

### Risks
- Auto-achieve on update must happen server-side — do not rely on Flutter to compute this

### Out of Scope for P9
- Linking goals to training logs
- AI-generated goal suggestions

---

## P10 — Discovery: Players, Tournaments, Venues

### Goal
Users can search for players by city/skill level, browse tournaments by city/status, and view/submit venues.

### Depends On
P2 (player profiles), P3 (tournaments exist)

> **Note:** P10 can be built in parallel with P5–P9 as long as P2 and P3 are done.

### Backend Scope
- `discovery/models.py` — `Venue` model
- `discovery/schemas.py` — `VenueCreate`, `VenueResponse`, `PlayerDiscoveryResponse`, `TournamentDiscoveryResponse`
- `discovery/service.py`:
  - `discover_players(city?, skill_level?, play_style?, page, page_size)` — queries `player_profiles` joined with `users`; excludes soft-deleted users
  - `discover_tournaments(city?, status?, format?, page, page_size)` — queries `tournaments`; excludes soft-deleted
  - `list_venues(city?)` — list venues optionally filtered by city
  - `submit_venue(submitter_id, data)` — create venue
- `discovery/router.py`:
  - `GET /api/v1/discovery/players`
  - `GET /api/v1/discovery/tournaments`
  - `GET /api/v1/discovery/venues`
  - `POST /api/v1/discovery/venues`
- Add DB indexes: `player_profiles.city`, `tournaments.city`, `tournaments.status`, `venues.city`

### Flutter Scope
- `features/discovery/data/discovery_repository.dart`
- `features/discovery/providers/discovery_provider.dart`
- `features/discovery/screens/discovery_screen.dart` — tab bar: "Players" | "Tournaments" | "Venues"
  - Players tab: city text field + skill level dropdown filter, paginated player cards (tap → public profile)
  - Tournaments tab: city text field + status filter, cards (tap → tournament detail)
  - Venues tab: city text field, venue cards, FAB to submit a new venue
- Add Discovery to bottom navigation bar

### DB / Migration Scope
- Migration 011: create `venues` table
- Migration 012: add indexes on `player_profiles.city`, `tournaments.city`, `tournaments.status`, `venues.city`, `matches.tournament_id`, `training_logs.user_id`

### Tests Required
- `test_discovery.py`:
  - `GET /discovery/players?city=Bengaluru` → returns players in that city only ✓
  - `GET /discovery/players?skill_level=ADVANCED` → filters correctly ✓
  - `GET /discovery/tournaments?status=REGISTRATION_OPEN` → correct subset ✓
  - Deleted tournaments do not appear ✓
  - `POST /discovery/venues` → creates venue ✓
  - `GET /discovery/venues?city=Chennai` → returns only Chennai venues ✓
  - Pagination: page 2 returns correct offset ✓

### Done Criteria
- [ ] All 7 discovery test cases pass
- [ ] Flutter: all three tabs functional with real data on device
- [ ] Index migration runs cleanly

### Risks
- City matching is case-insensitive `ILIKE` — ensure this is consistent across all discovery and list queries

### Out of Scope for P10
- GPS-based proximity
- Map integration
- Full-text search

---

## P11 — Offline Score Sync

### Goal
Score submissions made while offline are queued locally and automatically synced when connectivity is restored. Failures after 5 retries are surfaced to the user.

### Depends On
P6 (score submission API complete)

### Backend Scope
- Add `Idempotency-Key` header support to `POST /api/v1/matches/{id}/scores`:
  - If header present: check `idempotency_records` table for existing response
  - If found and < 24 hours old: return cached response
  - If not found: process normally, store `(key, response_body, created_at)` in `idempotency_records`
- `idempotency_records` table has no FK — it is a standalone cache table
- Note: the same idempotency logic via `PUT /matches/{id}/scores` (organiser correction) does NOT need idempotency — corrections are intentional replays

### Flutter Scope
- `core/sync/offline_queue.dart`:
  - Hive box `offline_score_queue`
  - `enqueue(match_id, sets, idempotency_key)` — add to queue
  - `drain()` — iterate queue, POST each with `Idempotency-Key` header, remove on 2xx, increment `retry_count` on failure
  - On 409 (conflict from server): remove entry, flag as conflict
  - After 5 retries: mark entry as `dead`
- `connectivity_plus` listener in `app.dart` — on connectivity restored, call `offline_queue.drain()`
- `features/matches/screens/score_submit_screen.dart` — modify: on submit, if offline → enqueue + show "Saved locally" snackbar; if online → POST directly (also with idempotency key, in case request times out mid-flight)
- `features/home/screens/home_screen.dart` — show "X unsynced scores" banner if queue is non-empty
- `features/matches/screens/sync_error_screen.dart` — list dead queue entries with option to dismiss

### DB / Migration Scope
- Migration 013: create `idempotency_records` table `(key TEXT PK, response_body JSONB, created_at TIMESTAMPTZ)`

### Tests Required
- `test_idempotency.py`:
  - POST score with idempotency key → 201 ✓
  - POST same idempotency key again (within 24h) → 200, same response body, no duplicate DB rows ✓
  - POST same key after 24h → treated as new request ✓

### Done Criteria
- [ ] All 3 idempotency test cases pass
- [ ] Flutter: submit score while offline (airplane mode) → entry appears in queue → restore connectivity → score submitted → match detail shows correct score
- [ ] After 5 failed retries, entry appears in sync error screen
- [ ] Online submit also sends idempotency key (prevents double submission on timeout)

### Risks
- `connectivity_plus` on Android may fire connectivity-restored events even when DNS resolution still fails — add a small delay + actual HTTP ping to health endpoint before draining queue
- Hive box must be opened before `runApp` — initialise in `main.dart` before `ProviderScope`

### Out of Scope for P11
- Offline tournament creation
- Offline registration
- Offline training log creation

---

## P12 — OTP Hardening + Score Idempotency Cleanup

### Goal
OTP brute-force protection is in place. Idempotency record cleanup runs. Small security gaps from P1 are closed.

### Depends On
P1 (OTP), P6 (scores), P11 (idempotency records exist)

### Backend Scope
- OTP rate limiting in `auth/service.py`:
  - Add `attempt_count` column to `otp_verifications`
  - On each failed `verify_otp`: increment `attempt_count`
  - If `attempt_count >= 5`: mark OTP as used (invalidate), return 429 with message "Too many attempts. Request a new OTP."
- Add `POST /auth/otp/request` basic abuse guard: if an unused, non-expired OTP already exists for the same phone number created within the last 60 seconds → return 429 "Please wait before requesting another OTP"
- Idempotency cleanup: `FastAPI` startup event — schedule a background task to delete `idempotency_records` where `created_at < NOW() - INTERVAL '24 hours'` (runs once on startup; acceptable for MVP — not a scheduled job)
- Confirm all endpoints that should require auth actually do (auth integration audit — manual review, no new code)

### Flutter Scope
- `features/auth/screens/otp_screen.dart` — handle 429 response: show "Too many attempts" message, disable resend button with countdown timer
- Handle 429 on "request OTP" with appropriate user message

### DB / Migration Scope
- Migration 014: add `attempt_count INTEGER DEFAULT 0` to `otp_verifications`

### Tests Required
- `test_auth_hardening.py`:
  - 5 failed OTP attempts → 6th returns 429, OTP invalidated ✓
  - Requesting new OTP within 60s → 429 ✓
  - Requesting new OTP after 60s → 200 ✓

### Done Criteria
- [ ] All 3 hardening test cases pass
- [ ] Flutter: 429 handled gracefully with user-facing message (no crash, no raw error)

### Risks
- In-memory rate limiting would be simpler but lost on restart — using `otp_verifications.attempt_count` is the right call for a single-process monolith

### Out of Scope for P12
- Full OTP rate limiting via Redis (post-MVP)
- IP-based rate limiting

---

## P13 — Production Hardening

### Goal
The system is deployable to a production environment with proper environment separation, logging, indexing, and a QA sign-off checklist completed.

### Depends On
All prior phases complete and all required tests passing

### Backend Scope
- `config.py` — add `ENV` enum: `development | staging | production`
- CORS: in production, only allow the Flutter app's origin (none for pure native app — CORS can be restricted to internal/admin only)
- Structured logging: add `request_id` (UUID generated per request) to all log lines via middleware
- All Alembic migrations reviewed: verify all FK constraints, NOT NULL constraints, and default values are correctly applied
- Confirm indexes from Migration 012 exist and are correct
- `requirements.txt` fully pinned with `pip freeze`
- `Dockerfile` for backend: slim Python 3.11 image, non-root user, health check
- Environment variable documentation in `README.md`: all required vars listed with descriptions and example values
- Remove any debug-only endpoints (none expected, but audit)
- S3-compatible storage abstraction stub in `common/storage.py` — interface only, local disk implementation — ready for Phase 2 profile photos

### Flutter Scope
- `core/network/api_endpoints.dart` — base URL configurable via `--dart-define=API_BASE_URL=...` at build time; no hardcoded URLs
- `android/` and `ios/` — app name, bundle ID, version number set correctly
- App icon set for both platforms
- Splash screen configured
- `flutter build apk --release` and `flutter build ios --release` both succeed with no warnings
- All screens handle: loading state, empty state, error state (no unhandled `AsyncError` exposures)
- Manual QA checklist (see below)

### DB / Migration Scope
- No new tables
- Run `alembic upgrade head` on a clean DB and verify all 14 migrations apply in sequence cleanly

### Tests Required (final gate)
- All tests from P1–P12 pass in CI against a clean test database
- `pytest --tb=short` exits 0
- Total test count: ≥ 90 test cases across all modules

### Manual QA Checklist (both Android and iOS)

**Auth**
- [ ] Register new phone number, enter OTP, land on home
- [ ] Log out, log back in
- [ ] Token auto-refresh (test by shortening expiry in dev env)

**Profile**
- [ ] Edit profile, verify changes persist
- [ ] View another user's public profile

**Tournament — Knockout**
- [ ] Create tournament, open registration
- [ ] Register 4 players (use 4 test accounts)
- [ ] Set seed order, close registration
- [ ] Generate bracket
- [ ] Submit scores for all matches, verify winner propagation
- [ ] Tournament marked COMPLETED

**Tournament — Round Robin**
- [ ] Create RR tournament, register 4 players, generate schedule
- [ ] Submit all match scores
- [ ] Standings table correct

**Training**
- [ ] Log a training session
- [ ] Create a goal, update progress, see ACHIEVED state

**Discovery**
- [ ] Search players by city
- [ ] Browse tournaments by city and status
- [ ] Submit a venue

**Offline Sync**
- [ ] Enter airplane mode, submit a score → "Saved locally" shown
- [ ] Exit airplane mode → score syncs automatically

### Done Criteria
- [ ] All automated tests pass (≥ 90 cases)
- [ ] All manual QA checklist items checked off
- [ ] `docker compose up` starts the full stack with no errors
- [ ] Backend Docker image builds and starts correctly
- [ ] Flutter release builds succeed for both platforms
- [ ] `README.md` complete with setup instructions, env var table, and run commands

### Risks
- iOS release build signing issues can block launch — have a provisioning profile ready before P13
- Database migration sequence must be deterministic — run `alembic downgrade base && alembic upgrade head` as final check

### Out of Scope for P13
- App Store / Play Store submission (treated as a separate operational task)
- Performance testing
- Penetration testing
- Profile photo upload (post-MVP)
- Push notifications (post-MVP)

---

## Dependency Graph

```
P0 (Scaffolding)
└── P1 (Auth)
    └── P2 (User Profile)
        ├── P3 (Tournament Core)
        │   └── P4 (Participant Registration)
        │       ├── P5 (Knockout Bracket)
        │       │   └── P6 (Score Submission)
        │       │       ├── P11 (Offline Sync)
        │       │       │   └── P12 (Hardening)
        │       │       └── P12 (Hardening)
        │       └── P7 (Round Robin) ← parallel with P5/P6
        └── P8 (Training Logs)
            └── P9 (Training Goals)
        └── P10 (Discovery) ← parallel with P5–P9
```

**Parallelisation opportunities:**
- P7 (Round Robin) can be built alongside P5 or P6 (different developer)
- P8 + P9 (Training) can be built by a second developer from P2 onwards
- P10 (Discovery) can start as soon as P2 + P3 are done
- Flutter and backend within any phase can be built in parallel once API shapes are agreed

---

## Test Gate Summary

| Before Starting | Required Tests Must Pass |
|---|---|
| P2 | P1 auth tests (10 cases) |
| P3 | P2 profile tests (6 cases) |
| P5 | P3 tournament tests (12 cases) + P4 participant tests (13 cases) |
| P6 | P5 bracket tests (11 cases) |
| P7 | P4 participant tests (13 cases) |
| P11 | P6 score tests (12 cases) |
| P12 | P1 + P6 + P11 tests |
| P13 | All prior tests (≥ 90 cases total) |

---

## Explicitly Out of Scope — Entire MVP

These items are not referenced in any phase and should be rejected if they surface during implementation:

- SMS provider (real OTP delivery) — wire in after MVP
- Push notifications
- Profile photo upload
- GPS/map-based venue discovery
- Doubles partner acceptance flow (partner must confirm invitation)
- Third-place playoff match
- Round robin tiebreakers beyond points
- Tournament entry fees / payments
- Social feed, likes, comments
- Chat / messaging
- Web app
- Admin dashboard
- Analytics / reporting
- OAuth (Google Sign-In, Apple Sign-In)
- Multi-language / i18n
- Dark mode (Material 3 system theme is acceptable default; explicit dark mode toggle is post-MVP)

---

*End of Implementation Roadmap*
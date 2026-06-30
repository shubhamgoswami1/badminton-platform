# Badminton Platform — Claude Context

**Last updated:** 2026-05-18 (post-audit review)

---

## Folder Structure

```
Badminton-platform/
├── backend/                        # FastAPI + SQLAlchemy 2.0 async + PostgreSQL
│   ├── admin/                      # Ban/unban users, delete tournament, audit log
│   ├── auth/                       # OTP + JWT flow
│   ├── common/                     # exceptions, response envelope, pagination, enums, dependencies
│   ├── discovery/                  # Player/tournament/venue discovery
│   ├── routers/                    # health.py only
│   ├── scores/                     # Match score submission, Elo, walkover
│   ├── tournaments/                # Tournament CRUD, bracket/, participant registration
│   │   └── bracket/                # knockout.py, round_robin.py (pure logic)
│   ├── training/                   # Training logs + goals
│   ├── users/                      # User model, player profile
│   ├── alembic/versions/           # 0001–0020 (0001–0016 in main branch; 0017–0020 in worktree only)
│   ├── scripts/seed_dev.py         # Idempotent dev seed (10 players, 4 tournaments, full match history)
│   └── tests/                      # 188 test cases across 20 test files
├── mobile/                         # Flutter (Dart), Riverpod 2.x, go_router, Dio
│   └── lib/
│       ├── core/
│       │   ├── network/            # DioClient, AuthInterceptor, ApiEndpoints
│       │   ├── router/             # app_router.dart, shell_scaffold.dart (NavigationBar M3)
│       │   ├── storage/            # SecureStorage (tokens), Prefs (flags)
│       │   ├── theme/              # AppTheme (Material 3), AppColors
│       │   ├── utils/
│       │   └── widgets/            # LoadingIndicator, ErrorView, EmptyState, AvatarWidget
│       └── features/
│           ├── auth/               # Phone entry, OTP screen, AuthProvider
│           ├── discovery/          # PlayerSearchScreen, PlayerProfileViewScreen
│           ├── home/               # HomeScreen (dynamic greeting, stat cards)
│           ├── matches/            # MatchesScreen, MatchDetailScreen, offline queue
│           ├── profile/            # ProfileScreen, EditProfileScreen, OnboardingScreen
│           ├── tournaments/        # TournamentsScreen (nearby/joined/hosted tabs),
│           │                       # TournamentDetailScreen, CreateTournamentScreen,
│           │                       # TournamentFixturesScreen (matches + standings)
│           └── training/           # TrainingScreen (logs + goals tabs), AddLogScreen,
│                                   # AddGoalScreen, EditGoalScreen
├── docs/
│   ├── CLAUDE_CONTEXT.md           # This file
│   ├── IMPLEMENTATION_ROADMAP.md   # Phase-by-phase spec (P0–P13)
│   └── MVP_BUILD_PLAN.md
└── .claude/worktrees/sleepy-cori-968cb9/   # Separate worktree (backend-only changes, NOT yet merged)
```

---

## Branch State

| Branch | Contents |
|--------|----------|
| `claude/flutter-foundation` | Active main branch. Backend P0–P16 migrations + full Flutter app. |
| `claude/sleepy-cori-968cb9` (worktree) | 7 additional backend-only commits **not yet merged**: Elo/standings, training `intensity` field, goal player endpoint, discovery refinements, match `updated_at`+`version`, admin module, seed data. |

**IMPORTANT:** Until the worktree is merged, running the Flutter app against the main-branch backend will cause mismatch on `intensity` (training logs) and `version`/`updated_at` (matches offline queue).

---

## Completed Modules

### Backend (main branch, migrations 0001–0016)
- **Auth** — OTP request/verify, JWT access+refresh tokens, token rotation, logout, mock mode (`OTP_MOCK_MODE=true` accepts `123456`)
- **OTP Hardening** — `attempt_count` column, 5-attempt lockout → 429, 60s resend guard → 429
- **User Profile** — `GET/PUT /users/me/profile`, `GET /users/{id}/profile`, public profiles, reliability score
- **Player Search** — `GET /users/search` (name/city/skill), paginated
- **Tournaments** — Full CRUD, status transitions, soft-delete, nearby (haversine), my-hosted, my-joined
- **Participants** — Register/withdraw, seed order, capacity enforcement, doubles scaffold
- **Bracket — Knockout** — Power-of-2 expansion, byes, winner propagation to next match
- **Bracket — Round Robin** — Circle method, standings computed at query time (W=2pts, L=0pts)
- **Score Submission** — `POST /{id}/update-score` (intermediate), `POST /{id}/complete` (finalize + Elo), `POST /{id}/score` (one-shot), walkover
- **Elo Ratings** — Applied on match completion; `elo_applied` flag for idempotency; stored on `player_profiles`
- **Training Logs** — CRUD, date/session_type filter, own-only access
- **Training Goals** — CRUD, auto-ACHIEVED when `current_value >= target_value`, status filter
- **Discovery** — `GET /discovery/players` (city, Elo range, radius), `GET /discovery/tournaments`, venues CRUD
- **Health** — `GET /api/v1/health`

### Backend (worktree only — not yet in main branch)
- Training log `intensity` field (migration 0017)
- Player search indexes (migration 0018)
- Match `updated_at` + `version` for optimistic locking (migration 0019)
- Admin module: ban/unban user, soft-delete tournament, audit log, `GET /admin/logs` (migration 0020)
- `GET /training/goals/player/{user_id}` endpoint
- `GET /training/logs/player/{user_id}` endpoint

### Flutter (main branch — `claude/flutter-foundation`)
- **Auth flow** — Phone entry → OTP → home; token auto-refresh via Dio interceptor; logout clears tokens
- **Profile** — View own profile, edit (display_name, city, skill_level, play_style, bio), SkillChip + ReliabilityBadge
- **Onboarding** — First-login profile setup screen
- **Tournaments** — Nearby (location-based), Joined, Hosted tabs; Create tournament form; Detail screen (join/start/fixtures)
- **Fixtures** — Knockout flat match list + Round Robin standings table (2-tab `TournamentFixturesScreen`)
- **Matches** — My matches (upcoming/ongoing/completed tabs); MatchDetailScreen with inline score form; offline queue with sync banner
- **Offline Queue** — SharedPreferences persistence, connectivity listener, sync-on-reconnect, conflict detection, `_SyncBanner` + `_SyncQueueSheet`
- **Training** — Logs list + add; Goals list + add + edit + delete + progress bar
- **Discovery** — Player search with Elo/radius filters; PlayerProfileViewScreen

---

## Important Models / Entities

### Backend key models
| Model | Table | Key fields |
|-------|-------|-----------|
| `User` | `users` | `id`, `phone_number`, `is_admin`, `is_banned`, `deleted_at` |
| `PlayerProfile` | `player_profiles` | `user_id`, `display_name`, `city`, `skill_level`, `play_style`, `bio`, `elo_rating`, `reliability_score`, `rating` |
| `Tournament` | `tournaments` | `id`, `organiser_id`, `format` (KNOCKOUT/ROUND_ROBIN), `status`, `bracket_generated`, `deleted_at` |
| `TournamentParticipant` | `tournament_participants` | `tournament_id`, `user_id`, `partner_user_id`, `seed_order` |
| `Match` | `matches` | `tournament_id`, `round`, `side_a/b_participant_id`, `winner_participant_id`, `next_match_id`, `status`, `version`, `updated_at`, `elo_applied` |
| `MatchScore` | `match_scores` | `match_id`, `set_number`, `score_a`, `score_b` |
| `TrainingLog` | `training_logs` | `user_id`, `logged_at`, `duration_minutes`, `session_type`, `notes`, `intensity` (worktree only) |
| `TrainingGoal` | `training_goals` | `user_id`, `title`, `metric`, `target_value`, `current_value`, `status`, `deadline` |
| `Venue` | `venues` | `name`, `city`, `address`, `submitter_id` |
| `AdminLog` | `admin_logs` | `admin_id`, `action`, `target_type`, `target_id`, `notes` (worktree only) |

### Flutter key providers
| Provider | State | Notifier |
|----------|-------|----------|
| `authProvider` | `AuthState` | `AuthNotifier` — login/logout/refresh |
| `profileProvider` | `ProfileState` | `ProfileNotifier` — load/update own profile |
| `nearbyTournamentsProvider` | `NearbyTournamentsState` | requires lat/lng |
| `myJoinedProvider` / `myHostedProvider` | `MyTournamentsState` | — |
| `tournamentDetailProvider(id)` | `TournamentDetailState` | join/start/load |
| `participantsProvider(id)` | `ParticipantsState` | load/join/remove/reload |
| `fixturesProvider(id)` | `FixturesState` | matches + standings |
| `matchDetailProvider(id)` | `MatchDetailState` | updateScore/completeMatch |
| `scoreQueueProvider` | `ScoreQueueState` | offline queue management |
| `trainingLogsProvider` | `TrainingLogsState` | CRUD logs |
| `goalsProvider` | `GoalsState` | CRUD goals |
| `discoveryProvider` | `DiscoveryState` | search players with filters |

---

## API Endpoints Completed

```
POST   /auth/otp/request
POST   /auth/otp/verify
POST   /auth/token/refresh
POST   /auth/logout

GET    /users/me
PUT    /users/me/profile
GET    /users/search
GET    /users/{id}/profile

POST   /tournaments
GET    /tournaments
GET    /tournaments/{id}
PUT    /tournaments/{id}
DELETE /tournaments/{id}
POST   /tournaments/{id}/status
GET    /tournaments/nearby
GET    /tournaments/my-hosted
GET    /tournaments/my-joined
POST   /tournaments/{id}/participants
GET    /tournaments/{id}/participants
DELETE /tournaments/{id}/participants/{pid}
PUT    /tournaments/{id}/participants/seed-order
POST   /tournaments/{id}/start
POST   /tournaments/{id}/bracket/generate
GET    /tournaments/{id}/bracket
GET    /tournaments/{id}/matches
GET    /tournaments/{id}/standings

GET    /matches/my
GET    /matches/{id}
GET    /matches/{id}/score
POST   /matches/{id}/score          ← one-shot submit + complete
POST   /matches/{id}/update-score   ← save sets, transition to IN_PROGRESS
POST   /matches/{id}/complete       ← finalize + Elo
POST   /matches/{id}/walkover

POST   /training/logs
GET    /training/logs
GET    /training/logs/{id}
PUT    /training/logs/{id}
DELETE /training/logs/{id}
POST   /training/goals
GET    /training/goals
GET    /training/goals/{id}
PUT    /training/goals/{id}
DELETE /training/goals/{id}

GET    /discovery/players
GET    /discovery/tournaments
GET    /discovery/venues
POST   /discovery/venues

GET    /api/v1/health

# Worktree only (not yet in main branch):
POST   /admin/ban-user
POST   /admin/unban-user
DELETE /admin/tournament
GET    /admin/logs
GET    /training/goals/player/{user_id}
GET    /training/logs/player/{user_id}
```

---

## Business Rules Already Implemented

**Auth**
- OTP TTL enforced; used OTPs rejected
- 5 failed attempts → OTP invalidated, 429 returned
- New OTP within 60s of previous → 429
- Banned users → 403 on all protected routes (enforced in `get_current_user`)

**Tournaments**
- Status machine: DRAFT → REGISTRATION_OPEN → REGISTRATION_CLOSED → IN_PROGRESS → COMPLETED/CANCELLED
- Organiser cannot register as participant in their own tournament
- Editing only allowed in DRAFT or REGISTRATION_OPEN status
- Soft-delete sets `deleted_at`; deleted tournaments return 404

**Participants**
- Duplicate registration → 409
- Registration past deadline → 409
- Registration when full → 409
- Withdrawal blocked if IN_PROGRESS or COMPLETED

**Bracket / Matches**
- Knockout: power-of-2 expansion, byes auto-assigned from bottom seeds
- BYE matches: status=BYE, winner set immediately, winner propagated to next match slot
- Score submission: organiser or match participant only (others → 403)
- Organiser can correct completed match scores
- Walkover: organiser only; sets winner to the present participant
- Final match completion → tournament status → COMPLETED
- Elo applied once per match (`elo_applied` flag); K=32 standard formula

**Round Robin**
- Circle method; W=2pts, L=0pts; standings computed at query time
- Standings tied on points share rank (no tiebreaker)

**Training Goals**
- Auto-ACHIEVED server-side when `current_value >= target_value` on update

**Response envelope**
- All endpoints return `{"data": ..., "error": null, "meta": {}}` via `ok()` helper
- Pagination meta: `{"page": N, "page_size": N, "total": N, "has_next": bool}`

---

## Pending / Incomplete Items

### Missing Flutter screens (not yet built)
1. `edit_tournament_screen.dart` — edit existing tournament (P3 spec)
2. Status transition buttons — "Open Registration", "Close Registration", "Cancel" (P3 spec; only "Start" exists)
3. Training log edit/delete — log cards have no edit/delete action; no `log_detail_screen.dart` (P8 spec)
4. Venues tab in discovery — backend ready, Flutter has players-only discovery screen (P10 spec)
5. Knockout bracket tree view — currently a flat list; spec P5 requires visual tree with connecting lines

### Missing backend work (main branch)
6. `idempotency_records` table + `Idempotency-Key` header support on `POST /matches/{id}/score` (P11 spec)
7. Flutter must send `Idempotency-Key` header on all score submissions
8. `test_idempotency.py` — 3 required test cases (P11 gate)

### Merge required
9. Merge `claude/sleepy-cori-968cb9` → `claude/flutter-foundation` to bring in migrations 0017–0020, admin module, intensity field, updated_at/version on matches

### Test gaps
10. `test_scores.py`: missing "non-participant non-organiser → 403", "BO3 needing all 3 sets", "negative score → 422", "correct completed match → new winner"
11. `test_admin.py`: exists only in worktree
12. OTP screen: server-side 429 should disable submit button (client has resend cooldown but not server-429 UI path)

---

## Known Assumptions

- `match_format` is stored per-tournament and inherited by all matches (BO1/BO3/BO5)
- Score endpoint naming deviates from spec (`update-score` / `complete` vs spec's `POST/PUT /scores`) — Flutter and backend agree with each other; do not rename without updating both
- `location` discovery uses haversine SQL (PostGIS not used); default radius 50km
- `skill_level` and `play_style` enum values: `BEGINNER`, `INTERMEDIATE`, `ADVANCED`, `PROFESSIONAL` / `ATTACKING`, `DEFENSIVE`, `ALL_ROUND`, `SERVE_VOLLEY`
- OTP mock mode: any phone + code `123456` when `OTP_MOCK_MODE=true`
- Doubles support: `partner_user_id` field exists on `TournamentParticipant` but full doubles bracket is a post-MVP feature
- Teams scaffold (`teams` table, migration 0015) is wired to DB but not used in business logic yet
- `reliability_score` defaults to `5.0`; decremented by post-MVP no-show logic
- Base URL configured via `--dart-define=API_BASE_URL=...`; dev default `http://10.0.2.2:8000/api/v1`

---

## Things Future Prompts Must Not Break

1. **Response envelope** — every endpoint must return `{"data": ..., "error": null, "meta": {}}`. Never return naked JSON.
2. **`get_current_user` dependency** — is_banned check lives here; do not bypass or duplicate it.
3. **Flutter provider pattern** — all providers are `StateNotifier` + `StateNotifierProvider`; do not introduce `AsyncNotifier` or `riverpod_generator` without migrating the whole feature.
4. **Score endpoint paths** — Flutter `ApiEndpoints` is wired to `update-score`, `complete`, `score`, `walkover`. Do not rename these backend routes.
5. **Migration numbering** — next migration after merge must be 0021. Never reuse a revision ID.
6. **Soft deletes** — `Tournament` and `User` use `deleted_at`; all list/detail queries must filter `deleted_at IS NULL`.
7. **Elo idempotency** — `elo_applied` flag on `Match` prevents double-application; do not remove this check.
8. **`bracket_generated` flag** — prevents regeneration; must be checked before generating any bracket.
9. **Auth interceptor** — Dio intercepts 401, calls refresh once, retries; logout on second 401. Do not add parallel retry logic.
10. **`go_router` shell route** — `ShellScaffold` wraps all authenticated routes; new authenticated screens must be added as sub-routes under the shell, not as top-level routes.
11. **Test database isolation** — each test uses `AsyncSession` from `conftest.py`'s `_engine` fixture with per-test transaction rollback; do not add global state or fixtures that commit across tests.
12. **`ok()` helper** — imported from `common.response`; all router handlers must use it, never `JSONResponse` directly.

"""
Dev seed script — populates a fresh local database with realistic demo data.

Usage
─────
    cd backend/
    python scripts/seed_dev.py

Prerequisites
─────────────
- DATABASE_URL in .env pointing at a running PostgreSQL instance
- All migrations applied:  alembic upgrade head
- OTP_MOCK_MODE=true  (default — OTP is always 123456)

What gets created
─────────────────
  Users / Profiles
    10 demo players with full profiles (name, city, skill level, Elo)
    1  organiser account  (+91 98765 00010)
    1  admin account      (+91 98765 00001)  ← also a player

  Tournaments
    "Mumbai Open 2026"         COMPLETED   8-player knockout, BO3
    "Bangalore Invitational"   IN_PROGRESS  4-player knockout, BO1  (2 of 3 matches done)
    "Delhi Spring Cup 2026"    REGISTRATION_OPEN  BO3 knockout
    "Chennai Masters"          DRAFT

  Training data  (for first 3 players)
    12 training logs  (variety of session types, past 14 days)
     6 goals          (mix of ACTIVE / ACHIEVED / ABANDONED)

Idempotency
───────────
Re-running the script is safe — existing phone numbers are skipped.
If ALL demo phones already exist the script exits with "already seeded".
"""

import asyncio
import sys
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Optional

# Allow running from backend/ root
sys.path.insert(0, str(Path(__file__).parent.parent))

import structlog
from sqlalchemy import select

from database import AsyncSessionLocal
from logging_config import configure_logging

configure_logging()
log = structlog.get_logger()

# ── Demo data constants ───────────────────────────────────────────────────────

PLAYERS = [
    # (phone, display_name, city, skill_level, play_style, bio, elo)
    ("+919876500001", "Rahul Sharma",  "Mumbai",    "ADVANCED",      "BOTH",    "National-circuit veteran. Aggressive smash style.", 1720),
    ("+919876500002", "Priya Patel",   "Delhi",     "INTERMEDIATE",  "SINGLES", "Former college champion, returning after a break.", 1520),
    ("+919876500003", "Arjun Kumar",   "Bangalore", "ADVANCED",      "SINGLES", "Fast footwork, net-play specialist.", 1680),
    ("+919876500004", "Kavya Nair",    "Hyderabad", "PROFESSIONAL",  "BOTH",    "State-level player, 3x district champion.", 1850),
    ("+919876500005", "Vikram Singh",  "Chennai",   "INTERMEDIATE",  "DOUBLES", "Club player with 5 years experience.", 1490),
    ("+919876500006", "Ananya Reddy",  "Pune",      "BEGINNER",      "SINGLES", "Just started — keen to improve quickly.", 1380),
    ("+919876500007", "Rohit Gupta",   "Mumbai",    "ADVANCED",      "SINGLES", "Power hitter, enjoys baseline rallies.", 1660),
    ("+919876500008", "Deepa Iyer",    "Bangalore", "INTERMEDIATE",  "BOTH",    "Consistent player, strong on defense.", 1510),
    ("+919876500009", "Sanjay Joshi",  "Delhi",     "ADVANCED",      "SINGLES", "Tactical player, mixed doubles specialist.", 1640),
    ("+919876500010", "Meera Shah",    "Mumbai",    "PROFESSIONAL",  "BOTH",    "Tournament organiser & active professional player.", 1800),
]

ORGANISER_PHONE = "+919876500010"   # Meera Shah
ADMIN_PHONE     = "+919876500001"   # Rahul Sharma

# Training log templates  (session_type, duration_minutes, intensity, notes)
_LOG_TEMPLATES = [
    ("PRACTICE",  90,  "HIGH",   "Worked on smash accuracy and cross-court drops."),
    ("FITNESS",   45,  "MEDIUM", "Agility ladder + court sprints."),
    ("DRILL",     60,  "HIGH",   "Multi-shuttle footwork drill."),
    ("MATCH",    120,  "HIGH",   "Friendly 3-set match vs club partner."),
    ("PRACTICE",  75,  "MEDIUM", "Serving and return drills."),
    ("REST",       0,  None,     "Active rest day — light stretching."),
    ("FITNESS",   50,  "HIGH",   "Interval running + core circuit."),
    ("DRILL",     45,  "MEDIUM", "Net-play touch and deception work."),
    ("PRACTICE",  60,  "LOW",    "Easy rally session to warm up after rest."),
    ("MATCH",     90,  "HIGH",   "Competitive practice match — lost 2-1."),
    ("FITNESS",   40,  "MEDIUM", "Gym session: legs + cardio."),
    ("DRILL",     70,  "HIGH",   "Overhead clears and attacking lifts."),
]

# Goal templates  (title, description, status, target_days_from_now)
_GOAL_TEMPLATES = [
    ("Win a local tournament",
     "Enter and win the next city-level knockout.",
     "ACTIVE",    60),
    ("Improve backhand clear consistency",
     "Hit 8/10 backhand clears to the back tramline in a drill session.",
     "ACTIVE",    30),
    ("Play 20 competitive matches this year",
     "Track match count across all tournaments and friendlies.",
     "ACTIVE",   180),
    ("Learn the deceptive net shot",
     "Master the wrist flick — coach demo watched, now practising.",
     "ACHIEVED", -10),   # target was 10 days ago → overdue, but marked achieved
    ("Complete fitness block",
     "Four weeks of structured gym + court conditioning.",
     "ACHIEVED", -30),
    ("Reduce unforced errors below 5 per set",
     "Too many simple mistakes costing easy points.",
     "ABANDONED",  0),
]


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _days_ago(n: int) -> datetime:
    return _now() - timedelta(days=n)


def _days_from_now(n: int) -> Optional[datetime]:
    if n == 0:
        return None
    return _now() + timedelta(days=n)


# ── Core helpers ──────────────────────────────────────────────────────────────


async def _get_or_create_user(db, phone: str):
    from users.models import User

    result = await db.execute(
        select(User).where(User.phone_number == phone, User.deleted_at.is_(None))
    )
    user = result.scalar_one_or_none()
    if user:
        return user, False

    user = User(phone_number=phone, is_verified=True)
    db.add(user)
    await db.flush()
    return user, True


async def _upsert_profile(db, user_id, display_name, city, skill_level, play_style, bio, elo):
    from users.models import PlayerProfile

    result = await db.execute(
        select(PlayerProfile).where(PlayerProfile.user_id == user_id)
    )
    profile = result.scalar_one_or_none()
    if profile:
        return profile

    profile = PlayerProfile(
        user_id=user_id,
        display_name=display_name,
        city=city,
        skill_level=skill_level,
        play_style=play_style,
        bio=bio,
        elo_rating=float(elo),
        matches_played=0,
        wins=0,
        losses=0,
        reliability_score=4.5 + (hash(phone) % 100) / 200,  # 4.5–5.0
    )
    db.add(profile)
    await db.flush()
    return profile


async def _seed_users_and_profiles(db) -> dict[str, uuid.UUID]:
    """Return phone → user_id mapping for all demo players."""
    phone_to_uid: dict[str, uuid.UUID] = {}
    created = 0

    for phone, name, city, skill, style, bio, elo in PLAYERS:
        user, is_new = await _get_or_create_user(db, phone)
        phone_to_uid[phone] = user.id
        if is_new:
            created += 1

        # Mark admin
        if phone == ADMIN_PHONE and not user.is_admin:
            user.is_admin = True

        await _upsert_profile(db, user.id, name, city, skill, style, bio, elo)

    await db.commit()
    log.info("seed_users", total=len(PLAYERS), created=created)
    return phone_to_uid


# ── Tournament helpers ────────────────────────────────────────────────────────


async def _create_tournament(db, organiser_id, title, city, fmt, match_fmt, play_type, description=None):
    from tournaments.models import Tournament
    from common.enums import TournamentStatus

    # Check idempotency — skip if title already exists for this organiser
    result = await db.execute(
        select(Tournament).where(
            Tournament.organiser_id == organiser_id,
            Tournament.title == title,
            Tournament.deleted_at.is_(None),
        )
    )
    existing = result.scalar_one_or_none()
    if existing:
        return existing, False

    from tournaments.schemas import TournamentCreate
    from common.enums import TournamentFormat, MatchFormat, PlayType
    import tournaments.service as t_svc

    data = TournamentCreate(
        title=title,
        description=description,
        city=city,
        format=TournamentFormat(fmt),
        match_format=MatchFormat(match_fmt),
        play_type=PlayType(play_type),
    )
    t = await t_svc.create_tournament(db, organiser_id, data)
    await db.commit()
    return t, True


async def _register_participants(db, tournament_id, user_ids: list[uuid.UUID]) -> list:
    """Register players and return participant objects."""
    import tournaments.service as t_svc
    participants = []
    for uid in user_ids:
        try:
            p = await t_svc.register_participant(db, tournament_id, uid)
            participants.append(p)
        except Exception:
            # Already registered or not open — fetch existing
            from tournaments.models import TournamentParticipant
            result = await db.execute(
                select(TournamentParticipant).where(
                    TournamentParticipant.tournament_id == tournament_id,
                    TournamentParticipant.user_id == uid,
                )
            )
            p = result.scalar_one_or_none()
            if p:
                participants.append(p)
    await db.commit()
    return participants


async def _transition(db, tournament, organiser_id, next_status):
    import tournaments.service as t_svc
    from common.enums import TournamentStatus

    if tournament.status == next_status:
        return tournament
    try:
        await t_svc.transition_status(db, tournament.id, organiser_id, TournamentStatus(next_status))
        await db.commit()
        await db.refresh(tournament)
    except Exception as e:
        log.warning("transition_skip", tournament=tournament.title, next=next_status, reason=str(e))
    return tournament


async def _generate_bracket(db, tournament, organiser_id):
    if tournament.bracket_generated:
        return
    import tournaments.service as t_svc
    try:
        await t_svc.generate_bracket(db, tournament.id, organiser_id)
        await db.commit()
        await db.refresh(tournament)
    except Exception as e:
        log.warning("bracket_skip", tournament=tournament.title, reason=str(e))


async def _get_pending_matches(db, tournament_id) -> list:
    from tournaments.models import Match
    from common.enums import MatchStatus

    result = await db.execute(
        select(Match).where(
            Match.tournament_id == tournament_id,
            Match.status == MatchStatus.PENDING.value,
        ).order_by(Match.round, Match.match_number)
    )
    return list(result.scalars().all())


async def _submit_score(db, match, organiser_id, sets):
    """Submit scores and auto-pick winner (side with most set wins)."""
    import scores.service as s_svc
    from scores.schemas import SubmitScoreRequest, SetScoreInput

    # Determine winner
    a_wins = sum(1 for s in sets if s[0] > s[1])
    b_wins = sum(1 for s in sets if s[1] > s[0])
    winner_id = match.side_a_participant_id if a_wins >= b_wins else match.side_b_participant_id

    if winner_id is None:
        log.warning("submit_score_skip", match_id=str(match.id), reason="no participants")
        return

    try:
        req = SubmitScoreRequest(
            sets=[SetScoreInput(set_number=i+1, side_a_score=a, side_b_score=b)
                  for i, (a, b) in enumerate(sets)],
            winner_participant_id=winner_id,
        )
        await s_svc.submit_score(db, match.id, organiser_id, req)
        await db.commit()
    except Exception as e:
        log.warning("submit_score_skip", match_id=str(match.id), reason=str(e))


async def _update_score_partial(db, match, organiser_id, sets):
    """Push partial scores to move match to IN_PROGRESS."""
    import scores.service as s_svc
    from scores.schemas import UpdateScoreRequest, SetScoreInput

    try:
        req = UpdateScoreRequest(
            sets=[SetScoreInput(set_number=i+1, side_a_score=a, side_b_score=b)
                  for i, (a, b) in enumerate(sets)],
        )
        await s_svc.update_score(db, match.id, organiser_id, req)
        await db.commit()
    except Exception as e:
        log.warning("update_score_skip", match_id=str(match.id), reason=str(e))


# ── Tournament scenarios ──────────────────────────────────────────────────────


async def _seed_completed_tournament(db, organiser_id, player_uids: list[uuid.UUID]):
    """8-player BO3 knockout — all matches completed, Elo applied."""
    t, created = await _create_tournament(
        db, organiser_id,
        title="Mumbai Open 2026",
        city="Mumbai",
        fmt="KNOCKOUT",
        match_fmt="BEST_OF_3",
        play_type="SINGLES",
        description="Annual city-level open knockout. 8 players, best of 3 sets.",
    )
    if not created and t.status == "COMPLETED":
        log.info("seed_tournament_skip", title=t.title, reason="already completed")
        return

    await _transition(db, t, organiser_id, "REGISTRATION_OPEN")
    await _register_participants(db, t.id, player_uids[:8])
    await _transition(db, t, organiser_id, "REGISTRATION_CLOSED")
    await _generate_bracket(db, t, organiser_id)
    await _transition(db, t, organiser_id, "IN_PROGRESS")

    # Round 1 — 4 QF matches (side A wins first 3, side B wins last)
    qf_scores = [
        [(21, 15), (21, 18)],          # match 1: 2-0
        [(21, 19), (18, 21), (21, 16)], # match 2: 2-1
        [(21, 13), (21, 11)],           # match 3: 2-0
        [(17, 21), (21, 18), (19, 21)], # match 4: B wins 2-1
    ]
    matches = await _get_pending_matches(db, t.id)
    for match, sets in zip(matches, qf_scores):
        await _submit_score(db, match, organiser_id, sets)

    # Round 2 — 2 SF matches
    sf_scores = [
        [(21, 17), (21, 19)],
        [(15, 21), (21, 19), (21, 18)],
    ]
    matches = await _get_pending_matches(db, t.id)
    for match, sets in zip(matches, sf_scores):
        await _submit_score(db, match, organiser_id, sets)

    # Final
    final_scores = [[(21, 18), (19, 21), (21, 17)]]
    matches = await _get_pending_matches(db, t.id)
    for match, sets in zip(matches, final_scores):
        await _submit_score(db, match, organiser_id, sets)

    await _transition(db, t, organiser_id, "COMPLETED")
    log.info("seed_tournament_done", title=t.title, status=t.status)


async def _seed_in_progress_tournament(db, organiser_id, player_uids: list[uuid.UUID]):
    """4-player BO1 knockout — SF done, final pending (IN_PROGRESS)."""
    t, created = await _create_tournament(
        db, organiser_id,
        title="Bangalore Invitational 2026",
        city="Bangalore",
        fmt="KNOCKOUT",
        match_fmt="BEST_OF_1",
        play_type="SINGLES",
        description="Fast-format invitational. Best of 1 set per match.",
    )
    if not created and t.status == "IN_PROGRESS":
        log.info("seed_tournament_skip", title=t.title, reason="already in progress")
        return

    await _transition(db, t, organiser_id, "REGISTRATION_OPEN")
    await _register_participants(db, t.id, player_uids[:4])
    await _transition(db, t, organiser_id, "REGISTRATION_CLOSED")
    await _generate_bracket(db, t, organiser_id)
    await _transition(db, t, organiser_id, "IN_PROGRESS")

    # Complete the 2 semi-finals, leave the final PENDING
    matches = await _get_pending_matches(db, t.id)
    sf_scores = [[(21, 15)], [(21, 18)]]
    for match, sets in zip(matches[:2], sf_scores):
        await _submit_score(db, match, organiser_id, sets)

    # Put the final IN_PROGRESS with a partial score
    remaining = await _get_pending_matches(db, t.id)
    if remaining:
        await _update_score_partial(db, remaining[0], organiser_id, [(11, 9)])

    log.info("seed_tournament_done", title=t.title, status=t.status)


async def _seed_registration_open_tournament(db, organiser_id, player_uids: list[uuid.UUID]):
    """BO3 knockout — registration open, 3 players already joined."""
    t, created = await _create_tournament(
        db, organiser_id,
        title="Delhi Spring Cup 2026",
        city="Delhi",
        fmt="KNOCKOUT",
        match_fmt="BEST_OF_3",
        play_type="SINGLES",
        description="Spring season knockout open to all skill levels.",
    )
    if not created and t.status == "REGISTRATION_OPEN":
        log.info("seed_tournament_skip", title=t.title, reason="already open")
        return

    await _transition(db, t, organiser_id, "REGISTRATION_OPEN")
    # Register only 3 of the 4 slots — leaves room to demonstrate join flow
    await _register_participants(db, t.id, player_uids[2:5])
    log.info("seed_tournament_done", title=t.title, status=t.status)


async def _seed_draft_tournament(db, organiser_id):
    """Just a DRAFT — demonstrates the creation step."""
    t, created = await _create_tournament(
        db, organiser_id,
        title="Chennai Masters 2026",
        city="Chennai",
        fmt="KNOCKOUT",
        match_fmt="BEST_OF_3",
        play_type="SINGLES",
        description="Upcoming invitational — planning in progress.",
    )
    log.info("seed_tournament_done", title=t.title, status=t.status)


# ── Training data ─────────────────────────────────────────────────────────────


async def _seed_training_data(db, user_ids: list[uuid.UUID]):
    """Create training logs and goals for the first 3 demo players."""
    import training.service as tr_svc
    from training.schemas import TrainingLogCreate, TrainingGoalCreate
    from common.enums import SessionType, IntensityLevel, GoalStatus
    from training.models import TrainingLog, TrainingGoal

    for i, uid in enumerate(user_ids[:3]):
        # Check if this user already has training data
        result = await db.execute(
            select(TrainingLog).where(TrainingLog.user_id == uid).limit(1)
        )
        if result.scalar_one_or_none():
            log.info("seed_training_skip", user_index=i, reason="data exists")
            continue

        # Logs — one per template, spread over the past 14 days
        for j, (stype, dur, intensity, notes) in enumerate(_LOG_TEMPLATES):
            logged_at = _days_ago(13 - j)
            data = TrainingLogCreate(
                session_type=SessionType(stype),
                duration_minutes=dur,
                intensity=IntensityLevel(intensity) if intensity else None,
                notes=notes,
                logged_at=logged_at,
            )
            await tr_svc.create_log(db, uid, data)

        # Goals — only for the first player (demonstrating all statuses)
        if i == 0:
            result_g = await db.execute(
                select(TrainingGoal).where(TrainingGoal.user_id == uid).limit(1)
            )
            if result_g.scalar_one_or_none() is None:
                for title, desc, status, target_days in _GOAL_TEMPLATES:
                    target_date = (
                        None if target_days == 0
                        else _days_from_now(target_days)
                    )
                    data = TrainingGoalCreate(
                        title=title,
                        description=desc,
                        target_date=target_date,
                    )
                    goal = await tr_svc.create_goal(db, uid, data)

                    # Set non-ACTIVE status manually (service always creates ACTIVE)
                    if status != "ACTIVE":
                        goal.status = status
                        if status == "ACHIEVED":
                            goal.completed_at = _now() - timedelta(days=abs(target_days))

        await db.commit()

    log.info("seed_training_done")


# ── Main entry ────────────────────────────────────────────────────────────────


async def seed() -> None:
    log.info("seed_start")

    async with AsyncSessionLocal() as db:
        # ── Users & profiles ──────────────────────────────────────────────────
        phone_to_uid = await _seed_users_and_profiles(db)

        # Check if we already had everyone
        from users.models import User
        count_result = await db.execute(
            select(User).where(
                User.phone_number.in_([p[0] for p in PLAYERS])
            )
        )
        existing = count_result.scalars().all()
        if len(existing) == len(PLAYERS):
            # All users pre-existed — check if tournaments are also done
            from tournaments.models import Tournament
            t_result = await db.execute(
                select(Tournament).where(Tournament.title == "Mumbai Open 2026")
            )
            if t_result.scalar_one_or_none():
                log.info("seed_already_done", hint="database appears to be seeded already")
                # Still continue — upserts are safe

        organiser_id = phone_to_uid[ORGANISER_PHONE]
        player_uids = [phone_to_uid[p[0]] for p in PLAYERS]

        # ── Tournaments ───────────────────────────────────────────────────────
        await _seed_completed_tournament(db, organiser_id, player_uids)
        await _seed_in_progress_tournament(db, organiser_id, player_uids[2:6])
        await _seed_registration_open_tournament(db, organiser_id, player_uids)
        await _seed_draft_tournament(db, organiser_id)

        # ── Training data ─────────────────────────────────────────────────────
        await _seed_training_data(db, player_uids)

    log.info("seed_complete", status="ok")
    _print_summary(phone_to_uid)


def _print_summary(phone_to_uid: dict) -> None:
    print()
    print("=" * 60)
    print("  DEV SEED COMPLETE")
    print("=" * 60)
    print()
    print("  OTP mock mode: use code  123456  for any phone number.")
    print()
    print("  Demo accounts")
    print("  ─────────────")
    for phone, name, city, skill, *_ in PLAYERS:
        tag = ""
        if phone == ADMIN_PHONE:
            tag = "  ← ADMIN"
        elif phone == ORGANISER_PHONE:
            tag = "  ← ORGANISER"
        print(f"  {phone}  {name:<18} {skill:<14} {city}{tag}")
    print()
    print("  Quick login (mock OTP):")
    print(f"    POST /api/v1/auth/otp/request  {{\"phone_number\": \"{PLAYERS[0][0]}\"}}")
    print(f"    POST /api/v1/auth/otp/verify   {{\"phone_number\": \"{PLAYERS[0][0]}\", \"otp\": \"123456\"}}")
    print()
    print("  Tournaments seeded:")
    print("    Mumbai Open 2026          COMPLETED   (8-player knockout)")
    print("    Bangalore Invitational    IN_PROGRESS (final match live)")
    print("    Delhi Spring Cup 2026     REGISTRATION_OPEN")
    print("    Chennai Masters 2026      DRAFT")
    print()
    print("  Docs: http://localhost:8000/docs")
    print("=" * 60)
    print()


if __name__ == "__main__":
    asyncio.run(seed())

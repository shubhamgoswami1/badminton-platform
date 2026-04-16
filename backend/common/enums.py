from enum import Enum


class TournamentFormat(str, Enum):
    KNOCKOUT = "KNOCKOUT"
    ROUND_ROBIN = "ROUND_ROBIN"


class MatchFormat(str, Enum):
    BEST_OF_1 = "BEST_OF_1"
    BEST_OF_3 = "BEST_OF_3"
    BEST_OF_5 = "BEST_OF_5"


class PlayType(str, Enum):
    SINGLES = "SINGLES"
    DOUBLES = "DOUBLES"
    MIXED_DOUBLES = "MIXED_DOUBLES"


class TournamentStatus(str, Enum):
    DRAFT = "DRAFT"
    REGISTRATION_OPEN = "REGISTRATION_OPEN"
    REGISTRATION_CLOSED = "REGISTRATION_CLOSED"
    IN_PROGRESS = "IN_PROGRESS"
    COMPLETED = "COMPLETED"
    CANCELLED = "CANCELLED"


class MatchStatus(str, Enum):
    PENDING = "PENDING"
    IN_PROGRESS = "IN_PROGRESS"
    COMPLETED = "COMPLETED"
    WALKOVER = "WALKOVER"
    BYE = "BYE"


class ParticipantStatus(str, Enum):
    REGISTERED = "REGISTERED"
    WITHDRAWN = "WITHDRAWN"
    DISQUALIFIED = "DISQUALIFIED"


class SkillLevel(str, Enum):
    BEGINNER = "BEGINNER"
    INTERMEDIATE = "INTERMEDIATE"
    ADVANCED = "ADVANCED"
    PROFESSIONAL = "PROFESSIONAL"


class PlayStyle(str, Enum):
    SINGLES = "SINGLES"
    DOUBLES = "DOUBLES"
    BOTH = "BOTH"


class SessionType(str, Enum):
    PRACTICE = "PRACTICE"
    FITNESS = "FITNESS"
    MATCH = "MATCH"
    DRILL = "DRILL"
    REST = "REST"


class GoalStatus(str, Enum):
    ACTIVE = "ACTIVE"
    ACHIEVED = "ACHIEVED"
    ABANDONED = "ABANDONED"


# Valid tournament status transitions
TOURNAMENT_STATUS_TRANSITIONS: dict[TournamentStatus, set[TournamentStatus]] = {
    TournamentStatus.DRAFT: {
        TournamentStatus.REGISTRATION_OPEN,
        TournamentStatus.CANCELLED,
    },
    TournamentStatus.REGISTRATION_OPEN: {
        TournamentStatus.REGISTRATION_CLOSED,
        TournamentStatus.CANCELLED,
    },
    TournamentStatus.REGISTRATION_CLOSED: {
        TournamentStatus.IN_PROGRESS,
        TournamentStatus.REGISTRATION_OPEN,
        TournamentStatus.CANCELLED,
    },
    TournamentStatus.IN_PROGRESS: {
        TournamentStatus.COMPLETED,
        TournamentStatus.CANCELLED,
    },
    TournamentStatus.COMPLETED: set(),
    TournamentStatus.CANCELLED: set(),
}

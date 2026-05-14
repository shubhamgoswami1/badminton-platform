abstract final class MatchStatus {
  static const pending = 'PENDING';
  static const inProgress = 'IN_PROGRESS';
  static const completed = 'COMPLETED';
  static const walkover = 'WALKOVER';
  static const bye = 'BYE';

  static String label(String v) =>
      const {
        pending: 'Pending',
        inProgress: 'In Progress',
        completed: 'Completed',
        walkover: 'Walkover',
        bye: 'Bye',
      }[v] ??
      v;
}

// ── Match ─────────────────────────────────────────────────────────────────

class Match {
  const Match({
    required this.id,
    required this.tournamentId,
    required this.round,
    required this.matchNumber,
    this.sideAParticipantId,
    this.sideBParticipantId,
    this.winnerParticipantId,
    required this.status,
    this.nextMatchId,
    this.winnerFeedsSide,
    this.scheduledAt,
    this.completedAt,
    required this.createdAt,
  });

  factory Match.fromJson(Map<String, dynamic> json) => Match(
        id: json['id'] as String,
        tournamentId: json['tournament_id'] as String,
        round: json['round'] as int,
        matchNumber: json['match_number'] as int,
        sideAParticipantId: json['side_a_participant_id'] as String?,
        sideBParticipantId: json['side_b_participant_id'] as String?,
        winnerParticipantId: json['winner_participant_id'] as String?,
        status: json['status'] as String,
        nextMatchId: json['next_match_id'] as String?,
        winnerFeedsSide: json['winner_feeds_side'] as String?,
        scheduledAt: json['scheduled_at'] as String?,
        completedAt: json['completed_at'] as String?,
        createdAt: json['created_at'] as String,
      );

  final String id;
  final String tournamentId;
  final int round;
  final int matchNumber;
  final String? sideAParticipantId;
  final String? sideBParticipantId;
  final String? winnerParticipantId;
  final String status;
  final String? nextMatchId;
  final String? winnerFeedsSide;
  final String? scheduledAt;
  final String? completedAt;
  final String createdAt;

  bool get isPending => status == MatchStatus.pending;
  bool get isInProgress => status == MatchStatus.inProgress;
  // Active = not yet finished; form should still be shown.
  bool get isActive => isPending || isInProgress;
  bool get isDone =>
      status == MatchStatus.completed ||
      status == MatchStatus.walkover ||
      status == MatchStatus.bye;
}

// ── Score data ────────────────────────────────────────────────────────────

class SetScore {
  const SetScore({
    required this.id,
    required this.matchId,
    required this.setNumber,
    required this.sideAScore,
    required this.sideBScore,
    this.submittedBy,
    required this.submittedAt,
  });

  factory SetScore.fromJson(Map<String, dynamic> json) => SetScore(
        id: json['id'] as String,
        matchId: json['match_id'] as String,
        setNumber: json['set_number'] as int,
        sideAScore: json['side_a_score'] as int,
        sideBScore: json['side_b_score'] as int,
        submittedBy: json['submitted_by'] as String?,
        submittedAt: json['submitted_at'] as String,
      );

  final String id;
  final String matchId;
  final int setNumber;
  final int sideAScore;
  final int sideBScore;
  final String? submittedBy;
  final String submittedAt;
}

class MatchScore {
  const MatchScore({
    required this.matchId,
    required this.status,
    this.winnerParticipantId,
    required this.sets,
  });

  factory MatchScore.fromJson(Map<String, dynamic> json) => MatchScore(
        matchId: json['match_id'] as String,
        status: json['status'] as String,
        winnerParticipantId: json['winner_participant_id'] as String?,
        sets: (json['sets'] as List<dynamic>)
            .map((e) => SetScore.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  final String matchId;
  final String status;
  final String? winnerParticipantId;
  final List<SetScore> sets;
}

// ── Composite for matches tab ─────────────────────────────────────────────

class MatchWithContext {
  const MatchWithContext({
    required this.match,
    required this.tournamentTitle,
    required this.organiserId,
  });

  /// Parse a single item from GET /matches/my (includes tournament context).
  factory MatchWithContext.fromMyMatchJson(Map<String, dynamic> json) =>
      MatchWithContext(
        match: Match.fromJson(json),
        tournamentTitle: json['tournament_title'] as String,
        organiserId: json['organiser_id'] as String,
      );

  final Match match;
  final String tournamentTitle;
  final String organiserId;
}

// ── Score submission DTOs ─────────────────────────────────────────────────

class SetScoreInput {
  SetScoreInput({
    required this.setNumber,
    this.sideAScore = 0,
    this.sideBScore = 0,
  });

  final int setNumber;
  int sideAScore;
  int sideBScore;

  Map<String, dynamic> toJson() => {
        'set_number': setNumber,
        'side_a_score': sideAScore,
        'side_b_score': sideBScore,
      };
}

class SubmitScoreRequest {
  const SubmitScoreRequest({
    required this.sets,
    required this.winnerParticipantId,
  });

  final List<SetScoreInput> sets;
  final String winnerParticipantId;

  Map<String, dynamic> toJson() => {
        'sets': sets.map((s) => s.toJson()).toList(),
        'winner_participant_id': winnerParticipantId,
      };
}

// ── Update-score DTO (no winner, PENDING → IN_PROGRESS) ───────────────────

class UpdateScoreRequest {
  const UpdateScoreRequest({required this.sets});

  final List<SetScoreInput> sets;

  Map<String, dynamic> toJson() => {
        'sets': sets.map((s) => s.toJson()).toList(),
      };
}

// ── Complete-match DTO (winner required, optional sets) ───────────────────

class CompleteMatchRequest {
  const CompleteMatchRequest({
    required this.winnerParticipantId,
    this.sets,
  });

  final String winnerParticipantId;
  final List<SetScoreInput>? sets;

  Map<String, dynamic> toJson() => {
        'winner_participant_id': winnerParticipantId,
        if (sets != null) 'sets': sets!.map((s) => s.toJson()).toList(),
      };
}

// ── Match detail (GET /matches/{id} response) ─────────────────────────────
// Richer than Match: includes embedded sets, elo_applied, version.

class MatchDetail {
  const MatchDetail({
    required this.id,
    required this.tournamentId,
    required this.round,
    required this.matchNumber,
    this.sideAParticipantId,
    this.sideBParticipantId,
    this.winnerParticipantId,
    required this.status,
    required this.eloApplied,
    required this.version,
    this.scheduledAt,
    this.completedAt,
    required this.sets,
  });

  factory MatchDetail.fromJson(Map<String, dynamic> json) => MatchDetail(
        // Note: GET /matches/{id} returns match_id, not id.
        id: (json['match_id'] ?? json['id']) as String,
        tournamentId: json['tournament_id'] as String,
        round: json['round'] as int,
        matchNumber: json['match_number'] as int,
        sideAParticipantId: json['side_a_participant_id'] as String?,
        sideBParticipantId: json['side_b_participant_id'] as String?,
        winnerParticipantId: json['winner_participant_id'] as String?,
        status: json['status'] as String,
        eloApplied: json['elo_applied'] as bool? ?? false,
        version: json['version'] as int? ?? 1,
        scheduledAt: json['scheduled_at'] as String?,
        completedAt: json['completed_at'] as String?,
        sets: (json['sets'] as List<dynamic>? ?? [])
            .map((e) => SetScore.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  final String id;
  final String tournamentId;
  final int round;
  final int matchNumber;
  final String? sideAParticipantId;
  final String? sideBParticipantId;
  final String? winnerParticipantId;
  final String status;
  final bool eloApplied;
  final int version;
  final String? scheduledAt;
  final String? completedAt;
  final List<SetScore> sets;

  bool get isPending => status == MatchStatus.pending;
  bool get isInProgress => status == MatchStatus.inProgress;
  bool get isActive => isPending || isInProgress;
  bool get isDone =>
      status == MatchStatus.completed ||
      status == MatchStatus.walkover ||
      status == MatchStatus.bye;

  List<SetScore> get sortedSets =>
      [...sets]..sort((a, b) => a.setNumber.compareTo(b.setNumber));
}

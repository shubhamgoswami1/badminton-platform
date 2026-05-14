// Training domain models — mirrors backend training schemas.

// ── Session type ──────────────────────────────────────────────────────────────

abstract final class SessionType {
  static const practice = 'PRACTICE';
  static const fitness  = 'FITNESS';
  static const match    = 'MATCH';
  static const drill    = 'DRILL';
  static const rest     = 'REST';

  static const all = [practice, fitness, match, drill, rest];

  static String label(String v) =>
      const {
        practice: 'Practice',
        fitness:  'Fitness',
        match:    'Match',
        drill:    'Drill',
        rest:     'Rest',
      }[v] ??
      v;
}

// ── Intensity level ───────────────────────────────────────────────────────────

abstract final class IntensityLevel {
  static const low    = 'LOW';
  static const medium = 'MEDIUM';
  static const high   = 'HIGH';

  static const all = [low, medium, high];

  static String label(String v) =>
      const {
        low:    'Low',
        medium: 'Medium',
        high:   'High',
      }[v] ??
      v;
}

// ── TrainingLog ───────────────────────────────────────────────────────────────

class TrainingLog {
  const TrainingLog({
    required this.id,
    required this.userId,
    required this.sessionType,
    required this.durationMinutes,
    this.intensity,
    this.notes,
    required this.loggedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory TrainingLog.fromJson(Map<String, dynamic> json) => TrainingLog(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        sessionType: json['session_type'] as String,
        durationMinutes: json['duration_minutes'] as int,
        intensity: json['intensity'] as String?,
        notes: json['notes'] as String?,
        loggedAt: DateTime.parse(json['logged_at'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  final String id;
  final String userId;
  final String sessionType;
  final int durationMinutes;
  final String? intensity;
  final String? notes;
  final DateTime loggedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
}

// ── Create request ────────────────────────────────────────────────────────────

class TrainingLogCreate {
  const TrainingLogCreate({
    required this.sessionType,
    required this.durationMinutes,
    this.intensity,
    this.notes,
  });

  final String sessionType;
  final int durationMinutes;
  final String? intensity;
  final String? notes;

  Map<String, dynamic> toJson() => {
        'session_type': sessionType,
        'duration_minutes': durationMinutes,
        if (intensity != null) 'intensity': intensity,
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
      };
}

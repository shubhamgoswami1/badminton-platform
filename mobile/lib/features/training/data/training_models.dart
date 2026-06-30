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

// ── Goal status ───────────────────────────────────────────────────────────────

abstract final class GoalStatus {
  static const active    = 'ACTIVE';
  static const achieved  = 'ACHIEVED';
  static const abandoned = 'ABANDONED';

  static const all = [active, achieved, abandoned];

  static String label(String v) =>
      const {
        active:    'Active',
        achieved:  'Achieved',
        abandoned: 'Abandoned',
      }[v] ??
      v;
}

// ── TrainingGoal ──────────────────────────────────────────────────────────────

class TrainingGoal {
  const TrainingGoal({
    required this.id,
    required this.userId,
    required this.title,
    this.description,
    this.targetDate,
    required this.status,
    this.completedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory TrainingGoal.fromJson(Map<String, dynamic> json) => TrainingGoal(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        targetDate: json['target_date'] == null
            ? null
            : DateTime.parse(json['target_date'] as String),
        status: json['status'] as String,
        completedAt: json['completed_at'] == null
            ? null
            : DateTime.parse(json['completed_at'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  final String id;
  final String userId;
  final String title;
  final String? description;
  final DateTime? targetDate;
  final String status;
  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isActive => status == GoalStatus.active;
  bool get isAchieved => status == GoalStatus.achieved;
  bool get isOverdue =>
      isActive &&
      targetDate != null &&
      targetDate!.isBefore(DateTime.now());
}

// ── Create / Update request ───────────────────────────────────────────────────

class TrainingGoalCreate {
  const TrainingGoalCreate({
    required this.title,
    this.description,
    this.targetDate,
  });

  final String title;
  final String? description;
  final DateTime? targetDate;

  Map<String, dynamic> toJson() => {
        'title': title,
        if (description != null && description!.isNotEmpty)
          'description': description,
        if (targetDate != null)
          'target_date': targetDate!.toIso8601String().substring(0, 10),
      };
}

class TrainingGoalUpdate {
  const TrainingGoalUpdate({
    this.title,
    this.description,
    this.targetDate,
    this.status,
  });

  final String? title;
  final String? description;
  final DateTime? targetDate;
  final String? status;

  Map<String, dynamic> toJson() => {
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (targetDate != null)
          'target_date': targetDate!.toIso8601String().substring(0, 10),
        if (status != null) 'status': status,
      };
}

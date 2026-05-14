import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_indicator.dart';
import '../data/training_models.dart';
import '../providers/goals_provider.dart';
import '../providers/training_provider.dart';
import 'add_goal_screen.dart';
import 'add_log_screen.dart';
import 'edit_goal_screen.dart';

class TrainingScreen extends ConsumerStatefulWidget {
  const TrainingScreen({super.key});

  @override
  ConsumerState<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends ConsumerState<TrainingScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    Future.microtask(() {
      ref.read(trainingLogsProvider.notifier).load();
      ref.read(goalsProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _openAddLog() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const AddLogScreen(),
        fullscreenDialog: true,
      ),
    );
  }

  Future<void> _openAddGoal() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const AddGoalScreen(),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Training'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Log'),
            Tab(text: 'Goals'),
          ],
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              if (_tabController.index == 0) {
                ref.read(trainingLogsProvider.notifier).refresh();
              } else {
                ref.read(goalsProvider.notifier).refresh();
              }
            },
          ),
        ],
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _tabController,
        builder: (_, __) => _tabController.index == 0
            ? FloatingActionButton.extended(
                onPressed: _openAddLog,
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                icon: const Icon(Icons.add),
                label: const Text('Log Session'),
              )
            : FloatingActionButton.extended(
                onPressed: _openAddGoal,
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                icon: const Icon(Icons.flag_outlined),
                label: const Text('New Goal'),
              ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _LogTab(onAddTap: _openAddLog),
          _GoalsTab(onAddTap: _openAddGoal),
        ],
      ),
    );
  }
}

// ── Log tab ───────────────────────────────────────────────────────────────────

class _LogTab extends ConsumerWidget {
  const _LogTab({required this.onAddTap});

  final VoidCallback onAddTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(trainingLogsProvider);

    if (state.isLoading && state.logs.isEmpty) {
      return const LoadingIndicator();
    }

    if (state.error != null && state.logs.isEmpty) {
      return ErrorView(
        message: state.error!,
        onRetry: () =>
            ref.read(trainingLogsProvider.notifier).refresh(),
      );
    }

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(trainingLogsProvider.notifier).refresh(),
      child: ListView(
        padding:
            const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          // ── Weekly summary ─────────────────────────────────────────
          _WeeklySummaryCard(state: state),
          const SizedBox(height: 20),

          // ── Recent sessions header ─────────────────────────────────
          Text(
            'Recent Sessions',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 10),

          // ── Sessions list ──────────────────────────────────────────
          if (state.logs.isEmpty)
            EmptyState(
              icon: Icons.fitness_center_outlined,
              title: 'No sessions logged',
              subtitle:
                  'Tap "Log Session" to start tracking\nyour training.',
              action: TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Log Session'),
                onPressed: onAddTap,
              ),
            )
          else
            ...state.logs.map((log) => _LogCard(log: log)),
        ],
      ),
    );
  }
}

// ── Weekly summary card ───────────────────────────────────────────────────────

class _WeeklySummaryCard extends StatelessWidget {
  const _WeeklySummaryCard({required this.state});

  final TrainingLogsState state;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.calendar_today_outlined,
                    size: 16, color: AppColors.primary),
                const SizedBox(width: 6),
                Text(
                  'This week',
                  style:
                      Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _WeekStat(
                    label: 'Sessions',
                    value: '${state.weekSessionCount}',
                  ),
                ),
                Expanded(
                  child: _WeekStat(
                    label: 'Time',
                    value: state.weekSessionCount == 0
                        ? '0h'
                        : state.weekHours,
                  ),
                ),
                Expanded(
                  child: _WeekStat(
                    label: 'Streak',
                    value: '${state.streakDays}d',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekStat extends StatelessWidget {
  const _WeekStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 2),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

// ── Log card ──────────────────────────────────────────────────────────────────

class _LogCard extends StatelessWidget {
  const _LogCard({required this.log});

  final TrainingLog log;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final intensityColor = _intensityColor(log.intensity);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Session type icon ─────────────────────────────────────
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _sessionIcon(log.sessionType),
                color: AppColors.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),

            // ── Details ───────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        SessionType.label(log.sessionType),
                        style:
                            theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (log.intensity != null) ...[
                        const SizedBox(width: 8),
                        _IntensityBadge(
                          level: log.intensity!,
                          color: intensityColor,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${log.durationMinutes} min  ·  '
                    '${_formatDate(log.loggedAt)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  if (log.notes != null &&
                      log.notes!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      log.notes!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IntensityBadge extends StatelessWidget {
  const _IntensityBadge({required this.level, required this.color});

  final String level;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        IntensityLevel.label(level),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

// ── Goals tab ─────────────────────────────────────────────────────────────────

class _GoalsTab extends ConsumerWidget {
  const _GoalsTab({required this.onAddTap});

  final VoidCallback onAddTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(goalsProvider);

    if (state.isLoading && state.goals.isEmpty) {
      return const LoadingIndicator();
    }

    if (state.error != null && state.goals.isEmpty) {
      return ErrorView(
        message: state.error!,
        onRetry: () => ref.read(goalsProvider.notifier).refresh(),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(goalsProvider.notifier).refresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          // ── Progress summary ───────────────────────────────────────
          if (state.totalGoals > 0) ...[
            _GoalProgressCard(state: state),
            const SizedBox(height: 20),
          ],

          // ── Active goals ───────────────────────────────────────────
          if (state.activeGoals.isNotEmpty) ...[
            Text(
              'Active',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 10),
            ...state.activeGoals.map((g) => _GoalCard(goal: g)),
            const SizedBox(height: 20),
          ],

          // ── Achieved goals ─────────────────────────────────────────
          if (state.achievedGoals.isNotEmpty) ...[
            Text(
              'Achieved',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 10),
            ...state.achievedGoals.map((g) => _GoalCard(goal: g)),
            const SizedBox(height: 20),
          ],

          // ── Abandoned goals ────────────────────────────────────────
          () {
            final abandoned = state.goals
                .where((g) => g.status == GoalStatus.abandoned)
                .toList();
            if (abandoned.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Abandoned',
                  style:
                      Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.onSurfaceVariant,
                          ),
                ),
                const SizedBox(height: 10),
                ...abandoned.map((g) => _GoalCard(goal: g)),
              ],
            );
          }(),

          // ── Empty state ────────────────────────────────────────────
          if (state.goals.isEmpty)
            EmptyState(
              icon: Icons.flag_outlined,
              title: 'No goals set',
              subtitle:
                  'Set training goals to stay\nmotivated and focused.',
              action: TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('New Goal'),
                onPressed: onAddTap,
              ),
            ),
        ],
      ),
    );
  }
}

// ── Goal progress card ────────────────────────────────────────────────────────

class _GoalProgressCard extends StatelessWidget {
  const _GoalProgressCard({required this.state});

  final GoalsState state;

  @override
  Widget build(BuildContext context) {
    final total = state.totalGoals;
    final achieved = state.achievedCount;
    final progress = total == 0 ? 0.0 : achieved / total;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.flag_outlined,
                    size: 16, color: AppColors.primary),
                const SizedBox(width: 6),
                Text(
                  'Goal progress',
                  style:
                      Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                ),
                const Spacer(),
                Text(
                  '$achieved / $total',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: AppColors.outline,
                valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.success),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _ProgressStat(
                    label: 'Active',
                    value: '${state.activeGoals.length}'),
                const SizedBox(width: 20),
                _ProgressStat(
                    label: 'Achieved',
                    value: '$achieved',
                    color: AppColors.success),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressStat extends StatelessWidget {
  const _ProgressStat({
    required this.label,
    required this.value,
    this.color,
  });

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: color ?? AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

// ── Goal card ─────────────────────────────────────────────────────────────────

class _GoalCard extends ConsumerWidget {
  const _GoalCard({required this.goal});

  final TrainingGoal goal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final statusColor = _statusColor(goal.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await Navigator.of(context).push<bool>(
            MaterialPageRoute<bool>(
              builder: (_) => EditGoalScreen(goal: goal),
              fullscreenDialog: true,
            ),
          );
        },
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Status dot ────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // ── Content ───────────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      goal.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        decoration: goal.isAchieved
                            ? TextDecoration.lineThrough
                            : null,
                        color: goal.isAchieved
                            ? AppColors.onSurfaceVariant
                            : null,
                      ),
                    ),
                    if (goal.description != null &&
                        goal.description!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        goal.description!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _StatusBadge(
                          label: GoalStatus.label(goal.status),
                          color: statusColor,
                        ),
                        if (goal.targetDate != null) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.calendar_today_outlined,
                            size: 12,
                            color: goal.isOverdue
                                ? AppColors.error
                                : AppColors.onSurfaceVariant,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            _formatGoalDate(goal.targetDate!),
                            style:
                                theme.textTheme.labelSmall?.copyWith(
                              color: goal.isOverdue
                                  ? AppColors.error
                                  : AppColors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // ── Delete action ─────────────────────────────────────
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                color: AppColors.onSurfaceVariant,
                tooltip: 'Delete goal',
                onPressed: () => _confirmDelete(context, ref),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete goal?'),
        content: Text(
            'Remove "${goal.title}" permanently?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(goalsProvider.notifier).deleteGoal(goal.id);
    }
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

Color _statusColor(String status) {
  switch (status) {
    case GoalStatus.achieved:
      return AppColors.success;
    case GoalStatus.abandoned:
      return AppColors.onSurfaceVariant;
    default:
      return AppColors.primary;
  }
}

String _formatGoalDate(DateTime dt) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${dt.day} ${months[dt.month - 1]}';
}

// ── Helpers ───────────────────────────────────────────────────────────────────

Color _intensityColor(String? level) {
  switch (level) {
    case IntensityLevel.low:
      return AppColors.success;
    case IntensityLevel.high:
      return AppColors.error;
    default:
      return AppColors.warning;
  }
}

IconData _sessionIcon(String type) {
  switch (type) {
    case SessionType.fitness:
      return Icons.fitness_center;
    case SessionType.match:
      return Icons.sports;
    case SessionType.drill:
      return Icons.repeat;
    case SessionType.rest:
      return Icons.hotel;
    default:
      return Icons.sports_tennis;
  }
}

String _formatDate(DateTime dt) {
  final local = dt.toLocal();
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  const weekdays = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'
  ];
  return '${weekdays[local.weekday - 1]} ${local.day} ${months[local.month - 1]}';
}

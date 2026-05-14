import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_indicator.dart';
import '../data/training_models.dart';
import '../providers/training_provider.dart';
import 'add_log_screen.dart';

class TrainingScreen extends ConsumerStatefulWidget {
  const TrainingScreen({super.key});

  @override
  ConsumerState<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends ConsumerState<TrainingScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(trainingLogsProvider.notifier).load(),
    );
  }

  Future<void> _openAddLog() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const AddLogScreen(),
        fullscreenDialog: true,
      ),
    );
    // The notifier already prepended the new log on success; no extra refresh needed.
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Training'),
          bottom: const TabBar(
            tabs: [
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
              onPressed: () =>
                  ref.read(trainingLogsProvider.notifier).refresh(),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _openAddLog,
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add),
          label: const Text('Log Session'),
        ),
        body: TabBarView(
          children: [
            _LogTab(onAddTap: _openAddLog),
            const _GoalsPlaceholder(),
          ],
        ),
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

// ── Goals placeholder (out of scope for this phase) ───────────────────────────

class _GoalsPlaceholder extends StatelessWidget {
  const _GoalsPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.flag_outlined,
      title: 'No goals set',
      subtitle:
          'Set training goals to stay\nmotivated and focused.',
    );
  }
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

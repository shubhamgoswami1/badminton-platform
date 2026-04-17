import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/empty_state.dart';

class TrainingScreen extends StatelessWidget {
  const TrainingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {
            // TODO(P8): open log session / add goal sheet
          },
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add),
          label: const Text('Add'),
        ),
        body: TabBarView(
          children: [
            // Log tab
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Weekly summary card
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('This week', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: _WeekStat(label: 'Sessions', value: '0')),
                            Expanded(child: _WeekStat(label: 'Hours', value: '0')),
                            Expanded(child: _WeekStat(label: 'Streak', value: '0 days')),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Recent Sessions', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                EmptyState(
                  icon: Icons.fitness_center_outlined,
                  title: 'No sessions logged',
                  subtitle: 'Start tracking your training\nto see progress over time.',
                ),
              ],
            ),

            // Goals tab
            EmptyState(
              icon: Icons.flag_outlined,
              title: 'No goals set',
              subtitle: 'Set training goals to stay\nmotivated and focused.',
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

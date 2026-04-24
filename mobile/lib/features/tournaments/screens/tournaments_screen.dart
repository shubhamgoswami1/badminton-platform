import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/empty_state.dart';

class TournamentsScreen extends StatelessWidget {
  const TournamentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tournaments'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () {},
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          // TODO(P3): navigate to create tournament screen
        },
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Create'),
      ),
      body: Column(
        children: [
          // Filter chips
          const SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                _FilterChip(label: 'All', selected: true),
                SizedBox(width: 8),
                _FilterChip(label: 'Open'),
                SizedBox(width: 8),
                _FilterChip(label: 'In Progress'),
                SizedBox(width: 8),
                _FilterChip(label: 'My City'),
              ],
            ),
          ),
          Expanded(
            child: EmptyState(
              icon: Icons.emoji_events_outlined,
              title: 'No tournaments yet',
              subtitle: 'Create a tournament or check back\nwhen registration opens.',
              action: TextButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, this.selected = false});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {},
      selectedColor: AppColors.primaryLight.withValues(alpha: 0.18),
      checkmarkColor: AppColors.primary,
    );
  }
}

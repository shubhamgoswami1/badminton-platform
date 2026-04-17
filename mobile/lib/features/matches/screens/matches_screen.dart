import 'package:flutter/material.dart';

import '../../../core/widgets/empty_state.dart';

class MatchesScreen extends StatelessWidget {
  const MatchesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Matches'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Upcoming'),
              Tab(text: 'Completed'),
            ],
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            indicatorColor: Colors.white,
          ),
        ),
        body: const TabBarView(
          children: [
            _MatchList(isEmpty: true, emptyTitle: 'No upcoming matches'),
            _MatchList(isEmpty: true, emptyTitle: 'No completed matches'),
          ],
        ),
      ),
    );
  }
}

class _MatchList extends StatelessWidget {
  const _MatchList({required this.isEmpty, required this.emptyTitle});

  final bool isEmpty;
  final String emptyTitle;

  @override
  Widget build(BuildContext context) {
    if (isEmpty) {
      return EmptyState(
        icon: Icons.sports_outlined,
        title: emptyTitle,
        subtitle: 'Matches will appear here once\nyou join a tournament.',
      );
    }
    return const SizedBox.shrink();
  }
}

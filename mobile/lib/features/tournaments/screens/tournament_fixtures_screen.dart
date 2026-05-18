import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_indicator.dart';
import '../../matches/data/match_models.dart';
import '../data/tournament_models.dart';
import '../providers/fixtures_provider.dart';

class TournamentFixturesScreen extends ConsumerStatefulWidget {
  const TournamentFixturesScreen({super.key, required this.tournament});

  final Tournament tournament;

  @override
  ConsumerState<TournamentFixturesScreen> createState() =>
      _TournamentFixturesScreenState();
}

class _TournamentFixturesScreenState
    extends ConsumerState<TournamentFixturesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  bool get _showStandings =>
      widget.tournament.format == TournamentFormat.roundRobin;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _showStandings ? 2 : 1,
      vsync: this,
    );
    Future.microtask(
      () => ref
          .read(tournamentFixturesProvider(widget.tournament.id).notifier)
          .load(),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tournament;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          t.title,
          overflow: TextOverflow.ellipsis,
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          tabs: [
            const Tab(text: 'Fixtures'),
            if (_showStandings) const Tab(text: 'Standings'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref
                .read(tournamentFixturesProvider(t.id).notifier)
                .reload(),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _FixturesTab(tournament: t),
          if (_showStandings) _StandingsTab(tournamentId: t.id),
        ],
      ),
    );
  }
}

// ── Fixtures tab ──────────────────────────────────────────────────────────

class _FixturesTab extends ConsumerWidget {
  const _FixturesTab({required this.tournament});

  final Tournament tournament;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tournamentFixturesProvider(tournament.id));

    if (state.isLoading && state.matches.isEmpty) {
      return const LoadingIndicator();
    }

    if (state.error != null && state.matches.isEmpty) {
      return ErrorView(
        message: state.error!,
        onRetry: () =>
            ref.read(tournamentFixturesProvider(tournament.id).notifier).reload(),
      );
    }

    final realMatches =
        state.matches.where((m) => m.status != MatchStatus.bye).toList();

    if (realMatches.isEmpty) {
      return const EmptyState(
        icon: Icons.sports_outlined,
        title: 'No fixtures yet',
        subtitle: 'Matches will appear here once\nthe bracket is generated.',
      );
    }

    if (tournament.format == TournamentFormat.knockout) {
      return _KnockoutFixtures(
        state: state,
        tournament: tournament,
      );
    } else {
      return _RoundRobinFixtures(
        state: state,
        tournament: tournament,
      );
    }
  }
}

// ── Knockout: visual bracket tree view ───────────────────────────────────

class _KnockoutFixtures extends StatelessWidget {
  const _KnockoutFixtures({
    required this.state,
    required this.tournament,
  });

  final TournamentFixturesState state;
  final Tournament tournament;

  static const _cardWidth = 160.0;
  static const _cardHeight = 72.0;
  static const _roundGap = 40.0;  // horizontal gap between rounds
  static const _lineColor = AppColors.outline;

  @override
  Widget build(BuildContext context) {
    final byRound = state.byRound;
    final maxRound = state.maxRound;
    final sortedRounds = byRound.keys.toList()..sort();

    // Each slot height = card height + vertical gap
    const slotHeight = _cardHeight + 24.0;

    // Build FULL sorted lists per round including BYEs — used for slot math.
    // BYE slots must be counted so non-power-of-2 brackets align correctly.
    final fullMatchesByRound = {
      for (final r in sortedRounds)
        r: ((byRound[r] ?? [])..sort((a, b) => a.matchNumber.compareTo(b.matchNumber))),
    };

    // Build filtered lists (no BYEs) — used only for card rendering.
    final matchesByRound = {
      for (final r in sortedRounds)
        r: fullMatchesByRound[r]!
            .where((m) => m.status != MatchStatus.bye)
            .toList(),
    };

    // Total height is driven by full R1 slot count (includes BYEs).
    final r1FullCount = fullMatchesByRound[sortedRounds.first]!.length;
    final totalHeight = math.max(r1FullCount * slotHeight, slotHeight * 2);

    final bracketWidth = sortedRounds.length * (_cardWidth + _roundGap) + 16;

    return RefreshIndicator(
      onRefresh: () async {},
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Round labels row ──────────────────────────────────────
            SizedBox(
              width: bracketWidth,
              child: Row(
                children: sortedRounds.map((r) {
                  return SizedBox(
                    width: _cardWidth + _roundGap,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _knockoutRoundLabel(r, maxRound),
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            // ── Bracket grid ───────────────────────────────────────────
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: bracketWidth,
                height: totalHeight,
                child: CustomPaint(
                  painter: _BracketLinePainter(
                    rounds: sortedRounds,
                    // Painter receives FULL lists so slot positions are correct
                    // even for non-power-of-2 brackets.
                    fullMatchesByRound: fullMatchesByRound,
                    totalHeight: totalHeight,
                    cardWidth: _cardWidth,
                    cardHeight: _cardHeight,
                    roundGap: _roundGap,
                    slotHeight: slotHeight,
                    lineColor: _lineColor,
                  ),
                  child: Stack(
                    children: [
                      for (var ri = 0; ri < sortedRounds.length; ri++)
                        ..._buildRoundCards(
                          context,
                          round: sortedRounds[ri],
                          roundIndex: ri,
                          realMatches: matchesByRound[sortedRounds[ri]] ?? [],
                          fullMatches: fullMatchesByRound[sortedRounds[ri]] ?? [],
                          slotHeight: slotHeight,
                        ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Legend ────────────────────────────────────────────────
            const SizedBox(height: 16),
            _BracketLegend(tournament: tournament),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildRoundCards(
    BuildContext context, {
    required int round,
    required int roundIndex,
    required List<Match> realMatches,
    required List<Match> fullMatches,
    required double slotHeight,
  }) {
    final multiplier = math.pow(2, roundIndex).toInt();
    final thisSlotHeight = slotHeight * multiplier;
    final left = roundIndex * (_cardWidth + _roundGap);

    return realMatches.map((match) {
      // Use the match's absolute index in the FULL round list (including BYEs)
      // so cards align with connector lines even for non-power-of-2 brackets.
      final absIdx = fullMatches.indexWhere((m) => m.id == match.id);
      final effectiveIdx = absIdx >= 0 ? absIdx : 0;
      final top = effectiveIdx * thisSlotHeight + (thisSlotHeight - _cardHeight) / 2;

      return Positioned(
        left: left,
        top: top,
        width: _cardWidth,
        height: _cardHeight,
        child: _BracketMatchCard(
          match: match,
          tournament: tournament,
        ),
      );
    }).toList();
  }
}

// ── Bracket line painter ──────────────────────────────────────────────────

class _BracketLinePainter extends CustomPainter {
  const _BracketLinePainter({
    required this.rounds,
    required this.fullMatchesByRound,
    required this.totalHeight,
    required this.cardWidth,
    required this.cardHeight,
    required this.roundGap,
    required this.slotHeight,
    required this.lineColor,
  });

  final List<int> rounds;
  /// Full match lists including BYEs, sorted by matchNumber.
  /// Used so slot positions are correct for non-power-of-2 brackets.
  final Map<int, List<Match>> fullMatchesByRound;
  final double totalHeight;
  final double cardWidth;
  final double cardHeight;
  final double roundGap;
  final double slotHeight;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (var ri = 0; ri < rounds.length - 1; ri++) {
      final fullCurrent = fullMatchesByRound[rounds[ri]] ?? [];
      final fullNext = fullMatchesByRound[rounds[ri + 1]] ?? [];

      final multiplier = math.pow(2, ri).toInt();
      final currentSlot = slotHeight * multiplier;
      final nextMultiplier = math.pow(2, ri + 1).toInt();
      final nextSlot = slotHeight * nextMultiplier;

      final currentLeft = ri * (cardWidth + roundGap);
      final nextLeft = (ri + 1) * (cardWidth + roundGap);
      final midX = currentLeft + cardWidth + roundGap / 2;

      for (var ni = 0; ni < fullNext.length; ni++) {
        final nextMatch = fullNext[ni];
        // Skip BYE slots in the next round — no lines needed
        if (nextMatch.status == MatchStatus.bye) continue;

        // The two slots in current round that feed into fullNext[ni]
        final srcAIdx = ni * 2;
        final srcBIdx = ni * 2 + 1;

        final nextCenterY = ni * nextSlot + nextSlot / 2;

        // Source A: draw exit line only if the slot holds a real match
        if (srcAIdx < fullCurrent.length &&
            fullCurrent[srcAIdx].status != MatchStatus.bye) {
          final aCenterY = srcAIdx * currentSlot + currentSlot / 2;
          canvas.drawLine(
            Offset(currentLeft + cardWidth, aCenterY),
            Offset(midX, aCenterY),
            paint,
          );
          canvas.drawLine(
            Offset(midX, aCenterY),
            Offset(midX, nextCenterY),
            paint,
          );
        }

        // Source B: draw exit line only if the slot holds a real match
        if (srcBIdx < fullCurrent.length &&
            fullCurrent[srcBIdx].status != MatchStatus.bye) {
          final bCenterY = srcBIdx * currentSlot + currentSlot / 2;
          canvas.drawLine(
            Offset(currentLeft + cardWidth, bCenterY),
            Offset(midX, bCenterY),
            paint,
          );
          canvas.drawLine(
            Offset(midX, bCenterY),
            Offset(midX, nextCenterY),
            paint,
          );
        }

        // Horizontal entry line into the next-round match card
        canvas.drawLine(
          Offset(midX, nextCenterY),
          Offset(nextLeft, nextCenterY),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BracketLinePainter old) =>
      old.rounds != rounds || old.fullMatchesByRound != fullMatchesByRound;
}

// ── Compact bracket match card ────────────────────────────────────────────

class _BracketMatchCard extends StatelessWidget {
  const _BracketMatchCard({required this.match, required this.tournament});

  final Match match;
  final Tournament tournament;

  @override
  Widget build(BuildContext context) {
    final sideAWon = match.winnerParticipantId != null &&
        match.winnerParticipantId == match.sideAParticipantId;
    final sideBWon = match.winnerParticipantId != null &&
        match.winnerParticipantId == match.sideBParticipantId;
    final statusColor = _matchStatusColor(match.status);

    return GestureDetector(
      onTap: () => context.push(
        AppRoutes.matchDetailPath(match.id),
        extra: MatchWithContext(
          match: match,
          tournamentTitle: tournament.title,
          organiserId: tournament.organiserId,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: statusColor.withValues(alpha: 0.4),
            width: 1.5,
          ),
          color: Theme.of(context).colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            // ── Status bar ─────────────────────────────────────
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.7),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(7)),
              ),
            ),
            // ── Side A ─────────────────────────────────────────
            Expanded(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: sideAWon
                      ? AppColors.primary.withValues(alpha: 0.08)
                      : null,
                ),
                child: Row(
                  children: [
                    if (sideAWon)
                      const Icon(Icons.emoji_events,
                          size: 12, color: AppColors.warning)
                    else
                      const SizedBox(width: 12),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        match.sideAParticipantId != null
                            ? match.sideAParticipantId!.substring(0, 8)
                            : 'TBD',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: sideAWon
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: sideAWon
                              ? AppColors.primary
                              : match.sideAParticipantId != null
                                  ? AppColors.onSurface
                                  : AppColors.disabled,
                          fontFamily: match.sideAParticipantId != null
                              ? 'monospace'
                              : null,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // ── Divider ────────────────────────────────────────
            const Divider(height: 1, thickness: 0.5),
            // ── Side B ─────────────────────────────────────────
            Expanded(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: sideBWon
                      ? AppColors.primary.withValues(alpha: 0.08)
                      : null,
                ),
                child: Row(
                  children: [
                    if (sideBWon)
                      const Icon(Icons.emoji_events,
                          size: 12, color: AppColors.warning)
                    else
                      const SizedBox(width: 12),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        match.sideBParticipantId != null
                            ? match.sideBParticipantId!.substring(0, 8)
                            : 'TBD',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: sideBWon
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: sideBWon
                              ? AppColors.primary
                              : match.sideBParticipantId != null
                                  ? AppColors.onSurface
                                  : AppColors.disabled,
                          fontFamily: match.sideBParticipantId != null
                              ? 'monospace'
                              : null,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Bracket legend ────────────────────────────────────────────────────────

class _BracketLegend extends StatelessWidget {
  const _BracketLegend({required this.tournament});

  final Tournament tournament;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        _LegendDot(color: _matchStatusColor(MatchStatus.pending), label: 'Pending'),
        _LegendDot(color: _matchStatusColor(MatchStatus.inProgress), label: 'In Progress'),
        _LegendDot(color: _matchStatusColor(MatchStatus.completed), label: 'Completed'),
        _LegendDot(color: _matchStatusColor(MatchStatus.walkover), label: 'Walkover'),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: AppColors.onSurfaceVariant)),
      ],
    );
  }
}

// ── Round robin: grouped by round, simpler labels ─────────────────────────

class _RoundRobinFixtures extends StatelessWidget {
  const _RoundRobinFixtures({
    required this.state,
    required this.tournament,
  });

  final TournamentFixturesState state;
  final Tournament tournament;

  @override
  Widget build(BuildContext context) {
    final byRound = state.byRound;
    final sortedRounds = byRound.keys.toList()..sort();

    return RefreshIndicator(
      onRefresh: () async {},
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: sortedRounds.length,
        itemBuilder: (context, i) {
          final round = sortedRounds[i];
          final matches = byRound[round]!;
          return _RoundSection(
            label: 'Round $round',
            matches: matches,
            tournament: tournament,
          );
        },
      ),
    );
  }
}

// ── Round section (header + match cards) ─────────────────────────────────

class _RoundSection extends StatelessWidget {
  const _RoundSection({
    required this.label,
    required this.matches,
    required this.tournament,
  });

  final String label;
  final List<Match> matches;
  final Tournament tournament;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RoundHeader(label: label, matchCount: matches.length),
        const SizedBox(height: 6),
        ...matches.map(
          (m) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _FixtureMatchCard(
              match: m,
              tournament: tournament,
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _RoundHeader extends StatelessWidget {
  const _RoundHeader({required this.label, required this.matchCount});

  final String label;
  final int matchCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$matchCount ${matchCount == 1 ? 'match' : 'matches'}',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Expanded(child: Divider(indent: 8)),
        ],
      ),
    );
  }
}

// ── Fixture match card ────────────────────────────────────────────────────

class _FixtureMatchCard extends StatelessWidget {
  const _FixtureMatchCard({
    required this.match,
    required this.tournament,
  });

  final Match match;
  final Tournament tournament;

  @override
  Widget build(BuildContext context) {
    final statusColor = _matchStatusColor(match.status);
    final sideAWon = match.winnerParticipantId != null &&
        match.winnerParticipantId == match.sideAParticipantId;
    final sideBWon = match.winnerParticipantId != null &&
        match.winnerParticipantId == match.sideBParticipantId;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push(
          AppRoutes.matchDetailPath(match.id),
          extra: MatchWithContext(
            match: match,
            tournamentTitle: tournament.title,
            organiserId: tournament.organiserId,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // ── Side A ──────────────────────────────────────────────
              Expanded(
                child: _SideLabel(
                  participantId: match.sideAParticipantId,
                  isWinner: sideAWon,
                  alignment: CrossAxisAlignment.start,
                ),
              ),

              // ── Centre: status badge ─────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: statusColor.withValues(alpha: 0.35)),
                      ),
                      child: Text(
                        MatchStatus.label(match.status),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'M${match.matchNumber}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Side B ──────────────────────────────────────────────
              Expanded(
                child: _SideLabel(
                  participantId: match.sideBParticipantId,
                  isWinner: sideBWon,
                  alignment: CrossAxisAlignment.end,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SideLabel extends StatelessWidget {
  const _SideLabel({
    this.participantId,
    required this.isWinner,
    required this.alignment,
  });

  final String? participantId;
  final bool isWinner;
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final isStart = alignment == CrossAxisAlignment.start;

    return Column(
      crossAxisAlignment: alignment,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment:
              isStart ? MainAxisAlignment.start : MainAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isWinner && isStart) ...[
              const Icon(Icons.emoji_events,
                  size: 14, color: AppColors.warning),
              const SizedBox(width: 3),
            ],
            Flexible(
              child: Text(
                participantId != null
                    ? participantId!.substring(0, 8)
                    : 'TBD',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      isWinner ? FontWeight.bold : FontWeight.normal,
                  color: isWinner
                      ? AppColors.primary
                      : participantId != null
                          ? AppColors.onSurface
                          : AppColors.disabled,
                  fontFamily:
                      participantId != null ? 'monospace' : null,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isWinner && !isStart) ...[
              const SizedBox(width: 3),
              const Icon(Icons.emoji_events,
                  size: 14, color: AppColors.warning),
            ],
          ],
        ),
      ],
    );
  }
}

// ── Standings tab ─────────────────────────────────────────────────────────

class _StandingsTab extends ConsumerWidget {
  const _StandingsTab({required this.tournamentId});

  final String tournamentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tournamentFixturesProvider(tournamentId));

    if (state.isLoading && state.standings.isEmpty) {
      return const LoadingIndicator();
    }

    if (state.standings.isEmpty) {
      return const EmptyState(
        icon: Icons.leaderboard_outlined,
        title: 'No standings yet',
        subtitle:
            'Standings will appear here\nonce matches have been played.',
      );
    }

    return RefreshIndicator(
      onRefresh: () async => ref
          .read(tournamentFixturesProvider(tournamentId).notifier)
          .reload(),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _StandingsTable(standings: state.standings),
          const SizedBox(height: 16),
          const _StandingsLegend(),
        ],
      ),
    );
  }
}

class _StandingsTable extends StatelessWidget {
  const _StandingsTable({required this.standings});

  final List<StandingEntry> standings;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          // ── Header row ──────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: const _StandingsRow(
              rank: '#',
              player: 'Player',
              mp: 'P',
              wins: 'W',
              losses: 'L',
              points: 'Pts',
              diff: '+/-',
              isHeader: true,
            ),
          ),

          // ── Data rows ───────────────────────────────────────────────
          ...standings.asMap().entries.map((entry) {
            final i = entry.key;
            final s = entry.value;
            final isLast = i == standings.length - 1;
            final isTop = i == 0;

            return Container(
              decoration: BoxDecoration(
                color: isTop
                    ? AppColors.warning.withValues(alpha: 0.04)
                    : null,
                border: isLast
                    ? null
                    : const Border(
                        bottom: BorderSide(
                            color: AppColors.outline, width: 0.5)),
              ),
              child: _StandingsRow(
                rank: '${i + 1}',
                player: s.shortId,
                mp: '${s.matchesPlayed}',
                wins: '${s.wins}',
                losses: '${s.losses}',
                points: '${s.points}',
                diff: s.pointDiff >= 0 ? '+${s.pointDiff}' : '${s.pointDiff}',
                isHeader: false,
                isTop: isTop,
                pointDiff: s.pointDiff,
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _StandingsRow extends StatelessWidget {
  const _StandingsRow({
    required this.rank,
    required this.player,
    required this.mp,
    required this.wins,
    required this.losses,
    required this.points,
    required this.diff,
    required this.isHeader,
    this.isTop = false,
    this.pointDiff,
  });

  final String rank;
  final String player;
  final String mp;
  final String wins;
  final String losses;
  final String points;
  final String diff;
  final bool isHeader;
  final bool isTop;
  final int? pointDiff;

  @override
  Widget build(BuildContext context) {
    final textStyle = isHeader
        ? const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          )
        : TextStyle(
            fontSize: 13,
            fontWeight:
                isTop ? FontWeight.bold : FontWeight.normal,
            color: AppColors.onSurface,
          );

    Color? diffColor;
    if (!isHeader && pointDiff != null) {
      diffColor = pointDiff! > 0
          ? AppColors.success
          : pointDiff! < 0
              ? AppColors.error
              : AppColors.onSurfaceVariant;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          // Rank
          SizedBox(
            width: 24,
            child: Row(
              children: [
                if (isTop && !isHeader)
                  const Icon(Icons.emoji_events,
                      size: 14, color: AppColors.warning)
                else
                  Text(rank, style: textStyle),
              ],
            ),
          ),
          // Player
          Expanded(
            child: Text(
              player,
              style: textStyle.copyWith(fontFamily: 'monospace'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // P
          _Cell(text: mp, style: textStyle, width: 28),
          // W
          _Cell(text: wins, style: textStyle, width: 28),
          // L
          _Cell(text: losses, style: textStyle, width: 28),
          // Pts
          _Cell(
            text: points,
            style: textStyle.copyWith(
              fontWeight: FontWeight.bold,
              color: isHeader ? AppColors.primary : AppColors.secondary,
            ),
            width: 36,
          ),
          // +/-
          _Cell(
            text: diff,
            style: textStyle.copyWith(
              color: diffColor ?? textStyle.color,
              fontWeight: FontWeight.w600,
            ),
            width: 44,
          ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.text,
    required this.style,
    required this.width,
  });

  final String text;
  final TextStyle style;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(text, style: style, textAlign: TextAlign.center),
    );
  }
}

class _StandingsLegend extends StatelessWidget {
  const _StandingsLegend();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        children: [
          _LegendItem(label: 'P', description: 'Played'),
          _LegendItem(label: 'W', description: 'Wins'),
          _LegendItem(label: 'L', description: 'Losses'),
          _LegendItem(label: 'Pts', description: 'Points'),
          _LegendItem(label: '+/-', description: 'Point diff'),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.label, required this.description});

  final String label;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
        const Text(
          ' = ',
          style: TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant),
        ),
        Text(
          description,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────

Color _matchStatusColor(String status) {
  switch (status) {
    case MatchStatus.completed:
      return AppColors.statusCompleted;
    case MatchStatus.walkover:
      return AppColors.statusCancelled;
    case MatchStatus.bye:
      return AppColors.statusDraft;
    default:
      return AppColors.statusInProgress;
  }
}

/// Returns a descriptive round label for knockout brackets.
/// e.g. maxRound=3, round=3 → "Final"
///          round=2 → "Semifinal"
///          round=1 → "Quarterfinal" (if maxRound=3)
String _knockoutRoundLabel(int round, int maxRound) {
  final fromEnd = maxRound - round;
  switch (fromEnd) {
    case 0:
      return 'Final';
    case 1:
      return 'Semifinal';
    case 2:
      return 'Quarterfinal';
    default:
      return 'Round $round';
  }
}

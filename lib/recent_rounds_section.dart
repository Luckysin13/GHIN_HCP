/// The "Recent rounds" list on Home.
///
/// Owns the row layout and expands from a recent summary to full history.
library;

import 'package:flutter/material.dart';

import 'design_tokens.dart';
import 'models.dart';

/// One row of the list, resolved by the caller.
///
/// Par depends on the tee the round was played from, so resolving it here
/// would mean this widget reaching into the store for one number. The caller
/// already has to look the round up to name it, so it does both at once.
class RecentRound {
  final Round round;
  final String courseName;

  /// Par for the holes actually played, not the full 18. A nine played from
  /// the 5th is scored against those nine's par, not half of 72.
  final int par;

  /// That tee's rating, or null when the tee is no longer on file. Null
  /// renders as a dash; a rating of 0.0 would be a course nobody plays.
  final double? rating;

  /// That tee's slope, or null when the tee is no longer on file. Same.
  final int? slope;

  const RecentRound({
    required this.round,
    required this.courseName,
    required this.par,
    this.rating,
    this.slope,
  });

  /// Gross score minus par. Negative is under.
  int get toPar => round.totalGross - par;
}

class RecentRoundsSection extends StatefulWidget {
  final List<RecentRound> rows;
  final void Function(Round round) onEdit;
  final void Function(Round round) onDelete;

  /// How many rows to show before offering the full history.
  final int limit;

  const RecentRoundsSection({
    super.key,
    required this.rows,
    required this.onEdit,
    required this.onDelete,
    this.limit = 20,
  });

  @override
  State<RecentRoundsSection> createState() => _RecentRoundsSectionState();
}

class _RecentRoundsSectionState extends State<RecentRoundsSection> {
  bool showAll = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = showAll
        ? widget.rows
        : widget.rows.take(widget.limit).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Insets.xs,
            Insets.sm,
            Insets.xs,
            Insets.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'RECENT ROUNDS',
                style: AppType.meta.copyWith(
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: Insets.sm),
              if (visible.isNotEmpty)
                Text(
                  '${visible.length}',
                  style: AppType.meta.copyWith(
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.6,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (visible.isEmpty)
          const _EmptyRounds()
        else
          for (final row in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: Insets.sm),
              child: _RoundRow(
                key: ValueKey(row.round.id),
                data: row,
                onEdit: () => widget.onEdit(row.round),
                onDelete: () => widget.onDelete(row.round),
              ),
            ),
        if (widget.rows.length > widget.limit)
          Padding(
            padding: const EdgeInsets.only(top: Insets.xs, bottom: Insets.sm),
            child: Center(
              child: TextButton.icon(
                key: const ValueKey('recent-rounds-toggle'),
                onPressed: () => setState(() => showAll = !showAll),
                icon: Icon(
                  showAll ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                ),
                label: Text(showAll ? 'Show fewer rounds' : 'Show all rounds'),
              ),
            ),
          ),
      ],
    );
  }
}

class _RoundRow extends StatelessWidget {
  final RecentRound data;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _RoundRow({
    super.key,
    required this.data,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final round = data.round;
    final nine = round.holes.length == 9;

    return Dismissible(
      key: ValueKey(round.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: Insets.lg),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(Radii.card),
        ),
        child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
      ),
      onDismissed: (_) => onDelete(),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(Radii.card),
        child: InkWell(
          onTap: onEdit,
          borderRadius: BorderRadius.circular(Radii.card),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.card),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(
              Insets.md,
              Insets.md,
              Insets.sm,
              Insets.md,
            ),
            child: Row(
              children: [
                // The score leads, in a fixed-width badge. A scorecard is read
                // by scanning the numbers, and burying the total at the end of
                // a text line is what made this list slow to parse before.
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(Radii.control),
                  ),
                  child: Text(
                    '${round.totalGross}',
                    style: AppType.title.copyWith(
                      fontSize: 17,
                      fontFeatures: AppType.tabular,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(data.courseName, style: AppType.title),
                      const SizedBox(height: 2),
                      Text(
                        _date(round.playedAt),
                        style: AppType.meta.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: Insets.xs),
                      Text(
                        _meta(round, data, nine),
                        style: AppType.meta.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: Insets.sm),
                      Wrap(
                        spacing: Insets.sm,
                        runSpacing: Insets.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _ToPar(value: data.toPar),
                          _ChBadge(value: round.courseHandicap),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Insets.xs),
                _RoundButton(
                  tooltip: 'Delete round',
                  icon: Icons.delete_outline,
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The course facts are separate from the date so neither is clipped on
  /// narrow screens.
  static String _meta(Round round, RecentRound data, bool nine) => [
    if (nine) '${round.holes.length} holes',
    'Par ${data.par}',
    'Rating ${_rating(data.rating)}',
    'Slope ${_slope(data.slope)}',
  ].join(' • ');

  /// One decimal, because that is the precision tee ratings are published at
  /// and a bare `71.243` implies a precision the source does not have.
  static String _rating(double? v) => v?.toStringAsFixed(1) ?? '—';

  static String _slope(int? v) => v?.toString() ?? '—';

  static String _date(DateTime d) {
    final local = d.toLocal();
    final m = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final y = (local.year % 100).toString().padLeft(2, '0');
    return '$m-$day-$y';
  }
}

/// Gross score against par, the one figure on the row that is actually a
/// judgement rather than a record.
///
/// Zero reads as "E", not "0": a scorecard says even, and a bare zero next to
/// a score badge reads like missing data.
class _ToPar extends StatelessWidget {
  final int value;
  const _ToPar({required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (text, color) = switch (value) {
      < 0 => ('$value', scheme.primary),
      0 => ('E', scheme.onSurfaceVariant),
      _ => ('+$value', scheme.error),
    };
    // Fixed width: the row otherwise reflows every time a round is one stroke
    // over instead of under, which is exactly the moment you are looking at it.
    return SizedBox(
      width: 32,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: AppType.title.copyWith(
          fontSize: 15,
          color: color,
          fontFeatures: AppType.tabular,
        ),
      ),
    );
  }
}

/// A secondary action in the row. Kept tighter than a stock [IconButton]
/// because two of them plus a score and two figures is a full row already.
class _RoundButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  const _RoundButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    icon: Icon(icon, size: 20),
    onPressed: onPressed,
    padding: EdgeInsets.zero,
    visualDensity: VisualDensity.compact,
    constraints: const BoxConstraints.tightFor(width: 44, height: 44),
  );
}

/// Course handicap as a small outlined pill, so it reads as a label rather
/// than another line of text competing with the score.
class _ChBadge extends StatelessWidget {
  final int? value;
  const _ChBadge({required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Insets.sm, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(
        value == null ? 'CH —' : 'CH $value',
        style: AppType.meta.copyWith(
          color: scheme.onSurfaceVariant,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _EmptyRounds extends StatelessWidget {
  const _EmptyRounds();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.xl,
        vertical: Insets.xxxl,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.sports_golf_outlined,
            size: 28,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: Insets.md),
          Text(
            'No rounds yet',
            style: AppType.title.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Insets.xs),
          Text(
            'Post your first score and it shows up here.',
            textAlign: TextAlign.center,
            style: AppType.meta.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'handicap_formats.dart';
import 'whs.dart';

/// Shows the Playing Handicap this golfer would get in each format, derived
/// from the unrounded Course Handicap for the current course, tee and hole
/// selection. Pure display; the Play page supplies the number.
///
/// Rendered as a collapsible list: the title and the Course Handicap it is
/// derived from stay visible, and the per-format allowances unfold under the
/// arrow when asked for.
class PlayingHandicapPanel extends StatelessWidget {
  final double? unroundedCourseHandicap;

  const PlayingHandicapPanel({
    super.key,
    required this.unroundedCourseHandicap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        initiallyExpanded: false,
        title: Text('Playing Handicap', style: theme.textTheme.titleMedium),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Text(
            'Course Handicap '
            '${unroundedCourseHandicap == null ? '—' : unroundedCourseHandicap!.toStringAsFixed(1)} • '
            'allowances per WHS Rule 6.2',
            style: theme.textTheme.bodySmall,
          ),
        ),
        children: [
          if (unroundedCourseHandicap == null)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Post three scores (54 holes) to see your Playing Handicap.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            )
          else
            for (final format in PlayFormat.values) _row(theme, format),
          const SizedBox(height: 8),
          Text(
            'Match play: strokes off the lowest Playing Handicap in the '
            'match. Alternate Shot combines the two Course Handicaps.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _row(ThemeData theme, PlayFormat format) {
    final unrounded = unroundedCourseHandicap;
    final value = format.appliesToSinglePlayer && unrounded != null
        ? playingHandicap(unrounded, format.allowance).toString()
        : '—';
    return Padding(
      key: ValueKey('ph-${format.name}'),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              format.displayName,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              format.allowanceLabel,
              style: theme.textTheme.bodySmall,
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
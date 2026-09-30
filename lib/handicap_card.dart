/// The handicap summary at the top of Home.
///
/// Split out of the page because it is the one panel whose whole job is to be
/// read at a glance, and because it is the piece most worth restyling without
/// unpicking the rest of the screen.
library;

import 'package:flutter/material.dart';

import 'design_tokens.dart';

class HandicapCard extends StatelessWidget {
  /// The index, or null when there is not enough scored history to compute
  /// one. Null is a normal state on a fresh account, not an error, so it gets
  /// a real presentation rather than a zero.
  final double? index;

  /// Rounds counted in the calculation, for the footnote.
  final int roundCount;

  /// Rounds still being uploaded, appended to the footnote when non-zero.
  final int pending;

  /// The trend line. Injected rather than computed so the card stays present
  /// and has no opinion about what a round is.
  final Widget trend;

  const HandicapCard({
    super.key,
    required this.index,
    required this.roundCount,
    required this.trend,
    this.pending = 0,
  });

  @override
  Widget build(BuildContext context) {
    const onCard = Color(0xFFF5FAF6);
    final hasIndex = index != null;

    return Card(
      color: Brand.forest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.card),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Brand.forest, Brand.fairway],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -12,
                bottom: -16,
                child: IgnorePointer(
                  child: Icon(
                    Icons.sports_golf,
                    size: 124,
                    color: Colors.white.withValues(alpha: 0.055),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Insets.lg,
                  vertical: Insets.md,
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final showWindowNote =
                        hasIndex && constraints.maxWidth >= _windowNoteMinWidth;
                    return Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'HANDICAP INDEX',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppType.meta.copyWith(
                                  color: onCard.withValues(alpha: 0.78),
                                  letterSpacing: 1.2,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: Insets.xs),
                              Text(
                                hasIndex ? index!.toStringAsFixed(1) : '--',
                                style: AppType.score.copyWith(
                                  fontSize: 42,
                                  height: 1,
                                  color: hasIndex
                                      ? onCard
                                      : onCard.withValues(alpha: 0.52),
                                ),
                              ),
                              if (!hasIndex) ...[
                                const SizedBox(height: Insets.xxs),
                                Text(
                                  'Post a few rounds and this fills in',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppType.meta.copyWith(
                                    fontSize: 10,
                                    color: onCard.withValues(alpha: 0.75),
                                  ),
                                ),
                              ],
                              const SizedBox(height: Insets.xs),
                              Text(
                                _roundLabel(roundCount),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppType.meta.copyWith(
                                  fontSize: 11,
                                  color: onCard.withValues(alpha: 0.9),
                                ),
                              ),
                              if (pending > 0) ...[
                                const SizedBox(height: Insets.xxs),
                                _Pill(text: '$pending syncing', color: onCard),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: Insets.md),
                        Expanded(
                          flex: 4,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (showWindowNote) ...[
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    'best of last 20',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppType.meta.copyWith(
                                      fontSize: 10,
                                      color: onCard.withValues(alpha: 0.68),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: Insets.xs),
                              ],
                              SizedBox(height: 36, child: trend),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _roundLabel(int n) =>
      n == 0 ? 'No rounds yet' : '$n ${n == 1 ? 'round' : 'rounds'}';

  /// Width below which the "best of last 20" note is dropped. Measured
  /// against the card's content box, not the screen: the card is what has to
  /// fit, and its width follows the gutter, not the device.
  static const double _windowNoteMinWidth = 300;
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  const _Pill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: Insets.sm, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(Radii.pill),
    ),
    child: Text(text, style: AppType.meta.copyWith(color: color, fontSize: 11)),
  );
}

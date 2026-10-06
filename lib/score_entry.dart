/// Parsing for a typed-in round total, e.g. "75" for 18 holes or "38" for a
/// nine. Pure Dart, no Flutter, so it is unit-tested directly in
/// test/score_entry_test.dart.
library;

import 'whs.dart';

/// Lowest and highest score a single hole can hold, matching the bounds the
/// Play page applies to its steppers.
const int minHoleScore = 1;
const int maxHoleScore = 12;

/// WHS Playing Conditions Calculation adjustments a venue may publish for a
/// round, from three strokes harder than normal to one easier (Rule 5.8).
/// Half-stroke steps, as PCC is announced to a decimal.
const List<double> pccOptions = [
  -1.0,
  -0.5,
  0.0,
  0.5,
  1.0,
  1.5,
  2.0,
  2.5,
  3.0,
];

/// A typed-in total, and the per-hole scores it was spread into.
///
/// [message] is null exactly when [scores] is a usable card, in which case
/// [scores] always sums to exactly [total].
class ScoreEntryResult {
  final int total;
  final List<int> scores;

  /// Human-readable reason the entry was rejected, or null when it is good.
  final String? message;

  ScoreEntryResult._(this.total, this.scores, this.message);

  ScoreEntryResult.ok(int total, List<int> scores)
    : this._(total, List.unmodifiable(scores), null);

  ScoreEntryResult.bad(String message) : this._(0, const [], message);

  bool get isValid => message == null;
}

/// Spreads [total] across [pars] as evenly as whole strokes allow.
///
/// A round entered as a single number has to become per-hole scores, because
/// that is what a [Round] stores and what the WHS cap is applied to. The
/// strokes above or below par are shared out evenly, and the remainder is
/// taken on the first holes, so the result always sums to exactly [total].
///
/// Note this is a derived breakdown, not observed play: 75 on a par 71 is
/// recorded as four bogeys and fourteen pars. Nothing is lost for handicap
/// purposes, because with no hole above par the Net Double Bogey cap never
/// binds and the adjusted gross is the total either way.
List<int> spreadTotal(int total, List<int> pars) {
  final n = pars.length;
  if (n == 0) return const [];
  final parTotal = pars.fold(0, (a, b) => a + b);
  final toPar = total - parTotal;
  // Truncating division, so the remainder carries the sign of the difference
  // and the two always recombine to exactly `toPar`.
  final whole = toPar ~/ n;
  final remainder = toPar - whole * n;
  final adjusted = remainder.abs(); // how many holes carry the extra stroke
  final bump = remainder.isNegative ? -1 : 1;
  return [
    for (var i = 0; i < n; i++) pars[i] + whole + (i < adjusted ? bump : 0),
  ];
}

/// Parses a single round [total] typed against the [pars] of the holes played.
///
/// Rejects anything that is not a whole number, and any total that cannot be
/// laid out as legal per-hole scores — a 400 on 18 holes would need 20s on
/// every hole, which is not a round, and silently clamping it would post a
/// score the golfer never played.
ScoreEntryResult parseRoundTotal(String raw, List<int> pars) {
  final text = raw.trim();
  if (text.isEmpty) {
    return ScoreEntryResult.bad(
      pars.isEmpty ? 'Pick a course and tee first' : 'Enter your total',
    );
  }
  final total = int.tryParse(text);
  if (total == null) {
    return ScoreEntryResult.bad('"$text" is not a number');
  }
  if (pars.isEmpty) return ScoreEntryResult.bad('Pick a course and tee first');

  final scores = spreadTotal(total, pars);
  final outOfRange = scores.any((s) => s < minHoleScore || s > maxHoleScore);
  if (outOfRange) {
    return ScoreEntryResult.bad(
      'A total of $total is not a score for ${pars.length} holes',
    );
  }
  return ScoreEntryResult.ok(total, scores);
}

/// Relative label for a nine of an 18-hole tee.
String nineLabel(int startHole) => startHole >= 9 ? 'Back 9' : 'Front 9';

/// Compact "9 holes • Back 9" / "18 holes" description of a selection.
String selectionLabel(int holesCount, int startHole) => holesCount == 9
    ? '9 holes • ${nineLabel(startHole)}'
    : holesCount == 18
    ? '18 holes'
    : '$holesCount holes played';

/// Hole-count choices this tee can support in the score-entry screens.
///
/// Nine or eighteen only; no partial counts between.
List<int> holeCountOptionsForTee(int teeHoleCount) => [
  9,
  if (teeHoleCount == 18) 18,
];

/// One hole's gross score capped at its posting maximum.
class AdjustedHole {
  final int par;
  final int strokeIndex;
  final int grossScore;
  final int adjustedScore;

  const AdjustedHole({
    required this.par,
    required this.strokeIndex,
    required this.grossScore,
    required this.adjustedScore,
  });

  /// True when the gross score exceeded the maximum and was cut down.
  bool get capped => adjustedScore < grossScore;
}

/// A card's gross scores capped at their posting maximums, with the total.
class PostingAdjustment {
  final List<AdjustedHole> holes;
  final int adjustedTotal;
  final bool wasAdjusted;

  const PostingAdjustment({
    required this.holes,
    required this.adjustedTotal,
    required this.wasAdjusted,
  });

  /// How many holes were cut down to their maximum.
  int get cappedCount => holes.where((h) => h.capped).length;
}

/// Caps per-hole gross scores at the maximum allowed for posting.
///
/// With an established [handicapIndex] each hole caps at net double bogey:
/// par plus two, plus the strokes received there (two or more on holes when
/// the Course Handicap is above 18, one back on the stroke-index order for
/// plus handicaps), per Rule 5.1. While establishing an initial index
/// ([handicapIndex] null) every hole caps at par plus five and
/// [courseHandicap] is ignored.
PostingAdjustment adjustScoresForPosting({
  required double? handicapIndex,
  required int courseHandicap,
  required List<({int par, int strokeIndex, int grossScore})> holes,
}) {
  final out = <AdjustedHole>[];
  var total = 0;
  var capped = false;
  for (final h in holes) {
    final max = handicapIndex == null
        ? h.par + 5
        : netDoubleBogeyCap(
            h.par,
            strokesReceived(courseHandicap, h.strokeIndex),
            courseHandicap: courseHandicap,
          );
    final adj = h.grossScore <= max ? h.grossScore : max;
    if (adj != h.grossScore) capped = true;
    total += adj;
    out.add(
      AdjustedHole(
        par: h.par,
        strokeIndex: h.strokeIndex,
        grossScore: h.grossScore,
        adjustedScore: adj,
      ),
    );
  }
  return PostingAdjustment(
    holes: out,
    adjustedTotal: total,
    wasAdjusted: capped,
  );
}

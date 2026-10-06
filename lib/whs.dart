import 'dart:math';

/// World Handicap System calculation engine.
/// Pure Dart, no dependencies. All functions are unit-tested in test/whs_test.dart.

/// Strokes received on a hole given a Course Handicap and stroke index (1-18).
int strokesReceived(int courseHandicap, int strokeIndex) {
  if (courseHandicap >= 0) {
    final base = courseHandicap ~/ 18;
    final rem = courseHandicap % 18;
    return base + (strokeIndex <= rem ? 1 : 0);
  } else {
    // Plus handicaps give strokes back from stroke index 18 down.
    final abs = -courseHandicap;
    final base = abs ~/ 18;
    final rem = abs % 18;
    final owed = base + (strokeIndex > 18 - rem ? 1 : 0);
    return -owed;
  }
}

/// Net Double Bogey cap for one hole.
int netDoubleBogeyCap(int par, int strokesOnHole, {int? courseHandicap}) {
  if (courseHandicap != null && courseHandicap > 54 && strokesOnHole >= 4) {
    return par + 5;
  }
  return par + 2 + strokesOnHole;
}

/// Adjusted gross: each hole capped at Net Double Bogey.
/// [scores], [pars], [strokeIndexes] must have equal length.
int adjustedGross({
  required List<int> scores,
  required List<int> pars,
  required List<int> strokeIndexes,
  required int courseHandicap,
  bool handicapIndexExists = true,
}) {
  assert(scores.length == pars.length && pars.length == strokeIndexes.length);
  var total = 0;
  for (var i = 0; i < scores.length; i++) {
    final strokes = strokesReceived(courseHandicap, strokeIndexes[i]);
    final cap = handicapIndexExists
        ? netDoubleBogeyCap(pars[i], strokes, courseHandicap: courseHandicap)
        : pars[i] + 5;
    total += min(scores[i], cap);
  }
  return total;
}

/// Score Differential for 18 holes.
double scoreDifferential({
  required num adjustedGrossScore,
  required double courseRating,
  required double slopeRating,
  double pcc = 0.0,
}) {
  final differential = scoreDifferentialUnrounded(
    adjustedGrossScore: adjustedGrossScore,
    courseRating: courseRating,
    slopeRating: slopeRating,
    pcc: pcc,
  );
  return (differential * 10).round() / 10.0;
}

double scoreDifferentialUnrounded({
  required num adjustedGrossScore,
  required double courseRating,
  required double slopeRating,
  double pcc = 0.0,
}) =>
    (113.0 / slopeRating) *
    (adjustedGrossScore.toDouble() - courseRating - pcc);

double expectedNineHoleScoreDifferential(double handicapIndex) =>
    0.52 * handicapIndex + 1.2;

double nineHoleScoreDifferentialUnrounded({
  required num adjustedGrossScore,
  required double courseRating,
  required double slopeRating,
  required double handicapIndex,
  double pcc = 0.0,
}) =>
    scoreDifferentialUnrounded(
      adjustedGrossScore: adjustedGrossScore,
      courseRating: courseRating,
      slopeRating: slopeRating,
      // The round's PCC is split between its played and expected nines.
      pcc: pcc / 2,
    ) +
    expectedNineHoleScoreDifferential(handicapIndex);

double nineHoleScoreDifferential({
  required num adjustedGrossScore,
  required double courseRating,
  required double slopeRating,
  required double handicapIndex,
  double pcc = 0.0,
}) {
  final differential = nineHoleScoreDifferentialUnrounded(
    adjustedGrossScore: adjustedGrossScore,
    courseRating: courseRating,
    slopeRating: slopeRating,
    handicapIndex: handicapIndex,
    pcc: pcc,
  );
  return (differential * 10).round() / 10.0;
}

/// Number of differentials to average given history length (WHS table).
int countToAverage(int n) {
  if (n < 3) return 0;
  if (n <= 5) return 1;
  if (n <= 8) return 2;
  if (n <= 11) return 3;
  if (n <= 14) return 4;
  if (n <= 16) return 5;
  if (n <= 18) return 6;
  if (n == 19) return 7;
  return 8;
}

/// Anti-sandbagging deduction for small scoring records (WHS table):
/// 3 scores -> -2.0, 4 scores -> -1.0, 6 scores -> -1.0, otherwise none.
double smallFieldAdjustment(int scoreCount) {
  if (scoreCount == 3) return -2.0;
  if (scoreCount == 4 || scoreCount == 6) return -1.0;
  return 0.0;
}

/// One posted round, reduced to what the handicap calculation needs.
///
/// A score differential on its own is not enough to work out a Handicap
/// Index: the caps depend on how long the scoring record is and how old it
/// is, so the date the score was played has to travel with it.
class ScoredRound {
  final DateTime playedAt;
  final double differential;
  final double? unroundedDifferential;
  final double? handicapIndexAtPlay;

  /// How many holes this count towards the 54-hole minimum. Nine-hole rounds
  /// post nine; anything between ten and seventeen holes counts what was
  /// played, as only nine- and eighteen-hole rounds can establish an index.
  final int holesPlayed;

  const ScoredRound({
    required this.playedAt,
    required this.differential,
    this.unroundedDifferential,
    this.handicapIndexAtPlay,
    this.holesPlayed = 18,
  });

  @override
  String toString() =>
      '${playedAt.toIso8601String().split('T').first}: ${differential.toStringAsFixed(1)}';
}

/// Scores needed before a Low Handicap Index exists at all.
const int lowHandicapMinimumScores = 20;

/// The window a Low Handicap Index is drawn from: the year preceding the
/// most recent score.
const Duration lowHandicapWindow = Duration(days: 365);

/// Handicap Index for a whole scoring record, with the WHS caps applied.
///
/// [rounds] may arrive in any order. The one-year window, the twenty-score
/// minimum and the cap all need the sequence of scores, so this walks the
/// record the way the handicap system does — every posted score re-calculates
/// the index — rather than treating the record as one number.
///
/// The index is the best-N average from [handicapIndex], capped against the
/// Low Handicap Index carried forward from the prior scoring day. After each
/// day's scores are calculated, that low is refreshed from issued indexes
/// inside [lowHandicapWindow]. A low that ages out between scores still caps
/// the next score before the refresh.
///
/// Note what the low index is not: it is not the lowest score differential.
/// A single great round is one round, not a handicap, and treating it as the
/// baseline pins the index for as long as the record lasts.
double? handicapIndexFromRecord(List<ScoredRound> rounds) {
  // Rule 5.2: at least 3 scores totalling at least 54 holes.
  if (rounds.length < 3) return null;
  final totalHoles = rounds.fold<int>(0, (sum, round) => sum + round.holesPlayed);
  if (totalHoles < 54) return null;
  final indexed = rounds.indexed.toList()
    ..sort((a, b) {
      final dateOrder = a.$2.playedAt.compareTo(b.$2.playedAt);
      return dateOrder != 0 ? dateOrder : a.$1.compareTo(b.$1);
    });
  final sorted = [for (final entry in indexed) entry.$2];
  final adjustedDiffs = <double>[];
  final issuedIndexes = <double?>[];
  double? low;
  double? hi;
  var dayStart = 0;
  while (dayStart < sorted.length) {
    var dayEnd = dayStart + 1;
    while (dayEnd < sorted.length &&
        _sameDay(sorted[dayStart].playedAt, sorted[dayEnd].playedAt)) {
      dayEnd++;
    }
    for (var i = dayStart; i < dayEnd; i++) {
      final round = sorted[i];
      adjustedDiffs.add(round.differential);

      final raw = round.unroundedDifferential ?? round.differential;
      final playedIndex = round.handicapIndexAtPlay;
      if (playedIndex != null) {
        final reduction = exceptionalScoreReduction(raw, playedIndex);
        if (reduction > 0) {
          final firstAffected = max(0, i - 19);
          for (var affected = firstAffected; affected <= i; affected++) {
            adjustedDiffs[affected] -= reduction;
          }
        }
      }
    }

    hi = handicapIndex(adjustedDiffs, lowHi: low);
    for (var i = dayStart; i < dayEnd; i++) {
      issuedIndexes.add(hi);
    }

    if (dayEnd >= lowHandicapMinimumScores) {
      final windowStart = DateTime(
        sorted[dayStart].playedAt.year,
        sorted[dayStart].playedAt.month,
        sorted[dayStart].playedAt.day,
      ).subtract(lowHandicapWindow);
      for (var j = lowHandicapMinimumScores - 1; j < dayEnd; j++) {
        final issued = issuedIndexes[j];
        if (issued == null || sorted[j].playedAt.isBefore(windowStart)) {
          continue;
        }
        if (low == null || issued < low) low = issued;
      }
    }
    dayStart = dayEnd;
  }
  return hi;
}

bool _sameDay(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

/// Exceptional Score Reduction required by Rule 5.9.
double exceptionalScoreReduction(double unroundedDifferential, double index) {
  final below = index - unroundedDifferential;
  if (below >= 10.0) return 2.0;
  if (below >= 7.0) return 1.0;
  return 0.0;
}

/// Handicap Index from differentials (oldest -> newest, uses last 20).
/// Returns null when fewer than 3 scores. Current WHS: NO 0.96 multiplier
/// (removed 2020), average rounded — not truncated — to one decimal,
/// small-record adjustment applied before the soft/hard cap vs [lowHi],
/// maximum index 54.0.
double? handicapIndex(List<double> differentials, {double? lowHi}) {
  if (differentials.length < 3) return null;
  final recent = differentials.length > 20
      ? differentials.sublist(differentials.length - 20)
      : List<double>.from(differentials);
  final sorted = List<double>.from(recent)..sort();
  final k = countToAverage(recent.length);
  final best = sorted.take(k).toList();
  var hi = (best.reduce((a, b) => a + b) / best.length * 10).round() / 10.0;
  hi += smallFieldAdjustment(recent.length);
  if (lowHi != null) {
    final rise = hi - lowHi;
    if (rise > 3.0) {
      hi = lowHi + 3.0 + (rise - 3.0) / 2.0; // soft cap
      if (hi - lowHi > 5.0) hi = lowHi + 5.0; // hard cap after soft cap
    }
  }
  if (hi > 54.0) hi = 54.0;
  return (hi * 10).round() / 10.0;
}

/// Course Handicap (rounded integer).
int courseHandicap({
  required double handicapIndex,
  required double slopeRating,
  required double courseRating,
  required int par,
}) => unroundedCourseHandicap(
  handicapIndex: handicapIndex,
  slopeRating: slopeRating,
  courseRating: courseRating,
  par: par,
).round();

double unroundedCourseHandicap({
  required double handicapIndex,
  required double slopeRating,
  required double courseRating,
  required int par,
}) => handicapIndex * (slopeRating / 113.0) + (courseRating - par);

/// Course Handicap for nine holes. Handicap Indices are recorded to a tenth
/// for whole rounds, so the nine-hole rule halving is also rounded to a tenth
/// before it is applied to the slope (Rule 6.1b Example).
int nineHoleCourseHandicap({
  required double handicapIndex,
  required double slopeRating,
  required double courseRating,
  required int par,
}) {
  final half = (handicapIndex / 2 * 10).round() / 10.0;
  return courseHandicap(
    handicapIndex: half,
    slopeRating: slopeRating,
    courseRating: courseRating,
    par: par,
  );
}

/// WHS Playing Handicap allowances (Rule 6.2).
const double individualStrokePlayAllowance = 0.95;
const double individualMatchPlayAllowance = 1.0;
const double fourBallStrokePlayAllowance = 0.85;
const double fourBallMatchPlayAllowance = 0.90;
const double foursomesStrokePlayAllowance = 0.50;
const double foursomesMatchPlayAllowance = 0.50;
const double best1Of4Allowance = 0.75;
const double best2Of4Allowance = 0.85;
const double best3Of4Allowance = 1.0;
const double best4Of4Allowance = 1.0;

/// Match-play strokes given, off the lowest Playing Handicap in the match.
int matchPlayStrokesGiven(int playingHandicap, int lowestPlayingHandicap) {
  return playingHandicap - lowestPlayingHandicap;
}

/// Foursomes stroke play: each pair plays off 50% of their combined
/// Course Handicap (Rule 6.2a(5), Rule 5).
int foursomesStrokePlayHandicap(int courseHandicapA, int courseHandicapB) {
  return ((courseHandicapA.toDouble() + courseHandicapB) * 0.50).round();
}

/// Foursomes match play: the higher-handicapped pair gives 50% of the
/// difference between the two combined Course Handicaps (Rule 6.2b).
int foursomesMatchPlayHandicap(
  int combinedHandicapA,
  int combinedHandicapB,
) => ((max(combinedHandicapA, combinedHandicapB) -
          min(combinedHandicapA, combinedHandicapB)) *
      0.50)
      .round();

/// Playing Handicap with allowance, rounded from the unrounded Course Handicap.
int playingHandicap(num courseHandicap, double allowance) {
  return (courseHandicap * allowance).round();
}

int playingHandicapFromIndex({
  required double handicapIndex,
  required double slopeRating,
  required double courseRating,
  required int par,
  required double allowance,
}) => playingHandicap(
  unroundedCourseHandicap(
    handicapIndex: handicapIndex,
    slopeRating: slopeRating,
    courseRating: courseRating,
    par: par,
  ),
  allowance,
);

/// Target (expected gross) score.
int targetScore(int parTotal, int courseHandicapValue) {
  return parTotal + courseHandicapValue;
}

/// Haversine yards between two lat/lon points.
double yardsBetween(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  double toRad(double d) => d * pi / 180.0;
  final dLat = toRad(lat2 - lat1);
  final dLon = toRad(lon2 - lon1);
  final a =
      sin(dLat / 2) * sin(dLat / 2) +
      cos(toRad(lat1)) * cos(toRad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return r * c * 1.09361;
}

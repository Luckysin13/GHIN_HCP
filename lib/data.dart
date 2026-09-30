import 'models.dart';

/// The one course that ships with the app, transcribed from a real Crystal
/// Lake scorecard (par 71, five tees).
///
/// Every yardage, par, rating and handicap index here comes off that card, so
/// the app is usable and its handicap maths is checkable against a real
/// round. Nothing is invented except [slope], which the card does not print —
/// see [_slopeFromYardageSpread] for how it is derived and why.
List<Course> seedCourses() => [crystalLake];

const _holeCount = 18;

/// Par for holes 1-18. The card prints it as two rows of nine with the
/// front-nine (35) and back-nine (36) subtotals and a course total of 71.
const _pars = [4, 4, 3, 5, 3, 4, 4, 4, 4, 5, 3, 4, 4, 4, 4, 4, 3, 5];

/// Men's handicap (stroke index) for holes 1-18, from the card's
/// "MEN'S HANDICAP" row.
const _strokeIndex = [
  12, 10, 16, 2, 18, 14, 8, 6, 4, //
  11, 15, 3, 13, 9, 1, 5, 17, 7,
];

/// Longest and shortest tees on the card, 6323 and 4805 yards.
const _longestYardage = 6323;
const _shortestYardage = 4805;

/// Slope of the shortest tee, the anchor the others are measured from.
///
/// The card gives ratings (70.4 down to 63.6) but no slope, and the handicap
/// index divides by slope, so a made-up number would quietly change every
/// handicap the app reports. Rather than leave it at zero — which would make
/// the index infinite — it is estimated from the only evidence the card
/// offers: how much longer this tee is than the shortest one.
///
/// About 58 yards of length is worth one rating point on a course of this
/// shape, which is the usual yardage-to-rating rule of thumb. That puts the
/// spread at 26 points end to end, a normal figure for a 1500-yard difference.
/// Red is pinned at 113 because a forward tee of this length is a typical 113,
/// and the rest follow from the yardages.
///
/// This is an estimate, not a printed figure. A course whose real slope
/// matters to a competitive handicap should be entered as a custom course
/// with the slope the club publishes.
final _slopeBase = 113;

int _slopeFromYardageSpread(int yardage) {
  final yardsPerPoint = (_longestYardage - _shortestYardage) / 26;
  final slope =
      _slopeBase + ((yardage - _shortestYardage) / yardsPerPoint).round();
  return slope.clamp(55, 155);
}

/// One tee box: [name] and [rating] as printed, [yards] as printed.
Tee _tee(String name, double rating, List<int> yards) {
  final total = yards.fold(0, (a, b) => a + b);
  return Tee(
    id: 'crystal-lake-${name.toLowerCase()}',
    name: name,
    rating: rating,
    slope: _slopeFromYardageSpread(total),
    holes: List.generate(
      _holeCount,
      (i) => HoleInfo(
        number: i + 1,
        par: _pars[i],
        yardage: yards[i],
        strokeIndex: _strokeIndex[i],
      ),
    ),
  );
}

final Course crystalLake = Course(
  id: 'crystal-lake',
  name: 'Crystal Lake Golf Club',
  city: '',
  state: '',
  tees: [
    // Tee order is longest first, the way the card prints them.
    _tee('Black', 70.4, [
      366, 374, 200, 516, 145, 364, 380, 379, 376, //
      490, 180, 397, 396, 355, 419, 334, 127, 525,
    ]),
    _tee('Combo', 69.4, [
      341, 374, 168, 489, 145, 364, 347, 341, 376, //
      490, 147, 369, 396, 355, 389, 334, 127, 525,
    ]),
    _tee('White', 68.3, [
      341, 347, 168, 489, 137, 335, 347, 341, 366, //
      464, 147, 369, 373, 329, 389, 304, 109, 492,
    ]),
    _tee('Yellow', 66.5, [
      321, 329, 129, 472, 119, 316, 326, 322, 348, //
      448, 133, 323, 352, 304, 364, 291, 95, 480,
    ]),
    _tee('Red', 63.6, [
      286, 264, 111, 407, 107, 284, 299, 291, 309, //
      382, 110, 286, 311, 269, 329, 256, 94, 410,
    ]),
  ],
);

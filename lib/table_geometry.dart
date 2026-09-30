import 'hocr.dart';
import 'scorecard_scan.dart';

/// Where each hole's column sits on the card, learned from the hole-number
/// header ("1 2 3 4 5 6 7 8 9 OUT 10 ... 18 IN TOT HCP NET").
///
/// This is the table geometry that plain text throws away. The header is the
/// most reliable line on the card — it is the largest print, and a misread
/// digit in it moves an anchor slightly rather than inventing a yardage — so
/// its word centres are the anchors, and every value on every other row is
/// matched to the nearest anchor instead of being consumed in order.
class TableColumns {
  /// Horizontal centre of each hole's column, hole 1 first.
  final List<double> centers;

  /// Half the typical distance between two columns: how far a value may sit
  /// from its column's centre and still be counted as belonging to it.
  final double tolerance;

  const TableColumns(this.centers, this.tolerance);

  static const empty = TableColumns(<double>[], 0);

  bool get isEmpty => centers.isEmpty;

  int get holes => centers.length;

  /// Which hole [x] belongs to, or null when it belongs to none of them.
  ///
  /// Nearest-anchor is right rather than round-to-nearest-slot because the
  /// columns are not evenly spaced (a two-digit hole number is wider than a
  /// one-digit one, and the OUT/IN/TOT columns are wider still), so slot
  /// arithmetic drifts at the right-hand end of the card.
  int? columnAt(double x) {
    if (centers.isEmpty) return null;
    var best = -1;
    var bestDist = double.infinity;
    for (var i = 0; i < centers.length; i++) {
      final d = (centers[i] - x).abs();
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    return bestDist <= tolerance ? best : null;
  }
}

/// The header row, if one of the rows is a usable hole-number header.
///
/// Accepted on the numbers alone rather than on the OUT/IN/TOT words: a bad
/// photo often loses those labels but keeps the digits, and the digits are
/// what the geometry is made of. A header is a run of 9 or 18 values where
/// each one is exactly the number of the column it sits in, and the values
/// increase left to right.
TableColumns? findTableColumns(List<HocrLine> lines) {
  for (final line in lines) {
    final numbers = [
      for (final w in line.ordered)
        if (w.number != null) (n: w.number!, x: w.centerX),
    ];
    if (numbers.length < 9) continue;
    // Find the longest run starting at 1 and counting up. A scorecard header
    // is exactly that; anything else (a yardage row) is not.
    var best = <({int n, double x})>[];
    for (var start = 0; start < numbers.length; start++) {
      if (numbers[start].n != 1) continue;
      final run = <({int n, double x})>[];
      for (var k = start; k < numbers.length; k++) {
        if (numbers[k].n != run.length + 1) break;
        run.add(numbers[k]);
      }
      if (run.length > best.length) best = run;
    }
    // Nine is a front-nine-only header, which still places its own nine
    // columns; a card with a back nine needs all eighteen.
    if (best.length < 9) continue;

    final centers = [for (final b in best) b.x];
    final gaps = <double>[
      for (var i = 1; i < centers.length; i++) centers[i] - centers[i - 1],
    ]..sort();
    if (gaps.isEmpty) continue;
    final median = gaps[gaps.length ~/ 2];
    if (median <= 0) continue;
    // A gap far wider than the typical one means the run is not evenly
    // spaced, so the anchors are not columns and matching to them would
    // scatter values across the wrong holes. Half the median is generous
    // enough for the wobble of a photographed page.
    if (gaps.last > median * 2.5) continue;

    return TableColumns(centers, median * 0.75);
  }
  return null;
}

/// What a row placed by x-position says about one tee box.
class PlacedRow {
  /// The tee box this row was read for, e.g. "Black".
  final String name;

  /// Yardage for each hole, 0 where the row's value for that hole was lost
  /// or impossible.
  final List<int> yards;

  /// Agreement with the OUT/IN/TOT values printed on the same row.
  final SubtotalCheck subtotals;

  const PlacedRow(this.name, this.yards, this.subtotals);

  /// How many holes this row actually read. More is better, up to 18.
  int get known => yards.where((y) => y != 0).length;
}

/// Places the numbers on one row into hole columns, using [columns].
///
/// Returns null when the row has no label to identify a tee box, since a row
/// of bare numbers could be the par row or a subtotal line.
///
/// A value is only kept when two things agree: it sits inside the column it
/// was matched to, and it is a length a hole could have. A value that fails
/// either test is dropped and its hole reads as unknown, which is the entire
/// reason for doing this. The value a neighbour holds stays with its own hole
/// instead of sliding over to fill the gap.
PlacedRow? placeRowByColumns(HocrLine line, TableColumns columns) {
  if (columns.isEmpty) return null;

  final label = _rowLabel(line);
  if (label == null) return null;

  final yards = List<int>.filled(columns.holes, 0);
  // Subtotal columns sit outside the hole columns, so they are read by
  // position too: three extra slots after the holes.
  final subtotalValues = <int>[];
  for (final w in line.ordered) {
    final n = w.number;
    if (n == null) continue;
    final col = columns.columnAt(w.centerX);
    if (col != null) {
      if (n < minYardage || n > maxYardage) continue; // impossible length
      yards[col] = n;
    } else {
      subtotalValues.add(n);
    }
  }

  return PlacedRow(
    teeNameFrom(label),
    yards,
    checkSubtotals(yards, subtotalValues),
  );
}

/// The tee name a row belongs to, from the words at its left.
///
/// Only the leading words are read: a label sits at the left of the row, and
/// picking up the first number as a label would hand every anonymous row the
/// name of hole 1. The match itself is the text parser's, so a row named by
/// the geometry pass and the same row named by the text pass come out with
/// one spelling.
String? _rowLabel(HocrLine line) {
  final words = line.ordered;
  if (words.isEmpty) return null;
  // Stop at the first number: everything after it is data, not a label.
  final labelWords = <String>[];
  for (final w in words) {
    if (w.number != null) break;
    labelWords.add(w.text);
  }
  if (labelWords.isEmpty) return null;
  return teeLabelFor(labelWords.join(' ').toUpperCase());
}

/// Reads a card from its hOCR boxes instead of its text.
///
/// Deliberately narrow. This pass only places tee-box yardage rows, because
/// that is where a lost digit does the most damage: the par row is all single
/// digits, and the handicap row is read correctly or not at all, so neither
/// gains anything from column geometry. Everything else — the par row, the
/// handicap index, the ratings, the tee names' spelling — is left to the text
/// parser, and the two results are merged like any other pair of reads.
ScorecardScan parseHocrGeometry(String hocr, {ScorecardScan? textScan}) {
  final lines = groupHocrLines(parseHocrWords(hocr));
  final columns = findTableColumns(lines);
  if (columns == null) return const ScorecardScan();

  // Tees seen more than once: a card printed twice on one page, or a second
  // block. Later blocks win, matching what the text parser does.
  final tees = <String, PlacedRow>{};
  final order = <String>[];
  for (final line in lines) {
    if (_rowLabel(line) == null) continue;
    final placed = placeRowByColumns(line, columns);
    if (placed == null) continue;
    // A row that read nothing is a label with no numbers on it, not a tee.
    if (placed.known == 0) continue;
    final prior = tees[placed.name];
    if (prior == null) order.add(placed.name);
    // Keep whichever read more holes, so a partial row does not replace a
    // whole one. Equal counts keep the first, which is the top block.
    if (prior == null || placed.known > prior.known) tees[placed.name] = placed;
  }

  return ScorecardScan(
    // Par and handicap come from the text read: geometry adds nothing to
    // rows of single digits, and taking them from here too would mean
    // trusting two disagreeing reads of the same row.
    pars: textScan?.pars ?? const [],
    rating: textScan?.rating,
    slope: textScan?.slope,
    hcp: textScan?.hcp ?? const [],
    parSubtotals: textScan?.parSubtotals ?? SubtotalCheck.none,
    tees: [
      for (final n in order)
        ScannedTee(
          name: n,
          yards: tees[n]!.yards,
          subtotals: tees[n]!.subtotals,
        ),
    ],
  );
}

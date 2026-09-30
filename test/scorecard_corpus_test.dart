// Card layouts the parser has to survive, beyond the one real card in
// scorecard_scan_test.dart. These are synthetic but shaped like real USGA
// output: printed OUT/IN/TOT subtotals beside every row, a men's and a
// women's block in one photo, non-color tee names, and rows read as
// fragments. Every total here is arithmetically correct, so any
// subtotal mismatch in a test is a parser bug and not a bad fixture.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghin_golf/scorecard_scan.dart';

/// A wide card: two blocks (men's then women's) in one photo, both listing
/// BLACK, with the second block's BLACK cut off at nine holes. The complete
/// row must win, and the two must never fuse into one 18-value tee.
const twoBlockCard = '''
PINE VALLEY COUNTRY CLUB
TEES     1     2     3     4     5     6     7     8     9   OUT   10    11    12    13    14    15    16    17    18    IN   TOT   RATING
PAR      4     3     4     5     4     3     4     4     4    35   4     4     3     4     5     4     4     3     4    35   70
BLACK   410   175   395   520   402   190   388   410   360  3250  355   405   168   392   498   380   400   182   365  3145  6395  72.1
WHITE   385   160   370   495   378   170   362   385   340  3045  330   378   152   368   470   355   375   165   340  2933  5978  70.2
MEN'S HANDICAP  1     3     5     7     9    11    13    15    17     -   2     4     6     8    10    12    14    16    18     -    -
TEES     1     2     3     4     5     6     7     8     9   OUT   10    11    12    13    14    15    16    17    18    IN   TOT   RATING
WOMEN'S HANDICAP  2     4     6     8    10    12    14    16    18     -   1     3     5     7     9    11    13    15    17     -    -
PAR      4     3     4     5     4     3     4     4     4    35   4     4     3     4     5     4     4     3     4    35   70
BLACK   410   175   395   520   402   190   388   410   360  3250
''';

/// A narrow card whose rows come back as nine numbers per line, a tee name
/// the color list does not know, and a rating/slope pair in the footer.
const splitRowCard = '''
OAK RIDGE GOLF CLUB
RATINGS
PAR      4  4  3  5  4  3  4  4  4  35  4  3  4  4  5  4  3  4  4  35  70
CHAMPIONSHIP TEES  440  455  200  540  460  175  445  470  450  3635  440  215  430  455  540  460  195  425  360  3520  7155
71.0/132
''';

/// The same real card, but OCR read the par row and the tee row as short
/// fragments on consecutive lines. Distances and pars are the verified
/// Crystal Lake pairing, so no hole can legitimately mismatch its par.
const fragmentCard = '''
CRYSTAL LAKE GOLF CLUB
NORTHFIELD, IL
PAR  4 4 3
5 3 4 4 4 4
5 3 4 4 4 4
4 3 5
BLACK  366  374  200
516  145  364
380  379  376  490
180  397  396  355
419  334  127  525
70.4/130
MEN'S HANDICAP  12  10  16  2  18  14  8  6  4  11  15  3  13  9  1  5  17  7
''';

void main() {
  group('two-block card', () {
    final scan = parseScorecardText(twoBlockCard);

    test('par comes from the block that reads as 18 holes', () {
      expect(scan.pars, [
        4, 3, 4, 5, 4, 3, 4, 4, 4, //
        4, 4, 3, 4, 5, 4, 4, 3, 4,
      ]);
      expect(scan.pars.fold(0, (a, b) => a + b), 70);
    });

    test('par agrees with the printed 35/35/70', () {
      expect(scan.parSubtotals.printed, isTrue);
      expect(scan.parSubtotals.ok, isTrue);
    });

    test('same-named tees from two blocks do not fuse', () {
      expect(scan.tees.length, 2);
      expect(scan.tees.map((t) => t.name), ['Black', 'White']);
      for (final t in scan.tees) {
        expect(t.yards.length, 18, reason: '${t.name} must be whole');
      }
    });

    test('the complete row wins over the block cut off at nine holes', () {
      final black = scan.tees.firstWhere((t) => t.name == 'Black');
      expect(black.yards.first, 410);
      expect(black.yards.last, 365);
    });

    test('every tee matches its printed subtotals', () {
      expect(scan.verifiedTees, 2);
      for (final t in scan.tees) {
        expect(t.subtotals.ok, isTrue, reason: t.name);
        expect(t.parMismatch, isEmpty, reason: t.name);
      }
    });

    test('per-tee ratings are kept', () {
      expect(scan.tees[0].rating, 72.1);
      expect(scan.tees[1].rating, 70.2);
    });

    test("men's row wins over women's as the index of record", () {
      expect(scan.hcp, [
        1, 3, 5, 7, 9, 11, 13, 15, 17, //
        2, 4, 6, 8, 10, 12, 14, 16, 18,
      ]);
    });
  });

  group('split rows on a narrow card', () {
    final scan = parseScorecardText(splitRowCard);

    test('nine numbers per line still make one 18-hole tee', () {
      expect(scan.tees.length, 1);
      expect(scan.tees.first.name, 'Championship');
      expect(scan.tees.first.yards.length, 18);
    });

    test('yardages are not shifted by the printed totals', () {
      expect(scan.tees.first.yards.first, 440);
      expect(scan.tees.first.yards[9], 440);
      expect(scan.tees.first.yards.last, 360);
    });

    test('yardage subtotals verify, front and back', () {
      final t = scan.tees.first;
      expect(t.subtotals.printed, isTrue);
      expect(t.subtotals.front, isTrue);
      expect(t.subtotals.back, isTrue);
      expect(t.subtotals.total, isTrue);
      expect(t.verified, isTrue);
    });

    test('par ignores the printed 35/35/70 and sums to 70', () {
      expect(scan.pars.fold(0, (a, b) => a + b), 70);
      expect(scan.parSubtotals.ok, isTrue);
    });

    test('no hole pairs an impossible yardage with its par', () {
      expect(scan.tees.first.parMismatch, isEmpty);
    });

    test('footer rating/slope is read once', () {
      expect(scan.rating, 71.0);
      expect(scan.slope, 132);
    });
  });

  group('rows read as fragments', () {
    final scan = parseScorecardText(fragmentCard);

    test('par fragments join across four lines', () {
      expect(scan.pars.length, 18);
      expect(scan.pars.fold(0, (a, b) => a + b), 71);
    });

    test('the printed front-nine par total is not read as a par', () {
      expect(scan.pars.every((p) => p >= 3 && p <= 5), isTrue);
    });

    test('yardage fragments join to one complete tee', () {
      expect(scan.tees.length, 1);
      expect(scan.tees.first.yards.length, 18);
      expect(scan.tees.first.yards.first, 366);
      expect(scan.tees.first.yards.last, 525);
    });

    test('rating/slope in the footer is not read as a yardage', () {
      expect(scan.tees.first.yards, isNot(contains(130)));
      expect(scan.slope, 130);
    });

    test("men's handicap row is read as the stroke index", () {
      expect(scan.hcp, [
        12, 10, 16, 2, 18, 14, 8, 6, 4, //
        11, 15, 3, 13, 9, 1, 5, 17, 7,
      ]);
    });

    test('no subtotals are claimed when the fragments print none', () {
      // A fragment card has no OUT/IN/TOT to check against, so the parser
      // must say "no opinion" rather than "verified".
      expect(scan.tees.first.subtotals.printed, isFalse);
      expect(scan.parSubtotals.printed, isFalse);
    });
  });
}

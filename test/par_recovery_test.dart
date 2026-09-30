// Reading a scorecard whose par row did not survive the photo.
//
// The motivating case is a real scan of the Crystal Lake card in which OCR
// turned the par row into letters — "(N v v v e v" — while the yardage rows
// came through exactly. Par is the smallest print on the card, so it is the
// first thing lost, and the yardages are the field that repeats (once per tee
// box) and therefore the one that survives. The pars here are the real card's.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghin_golf/scorecard_scan.dart';

/// Crystal Lake's real par row, and what OCR made of it.
const _realPars = [4, 4, 3, 5, 3, 4, 4, 4, 4, 5, 3, 4, 4, 4, 4, 4, 3, 5];
const _realTotal = 71;

const _black = [
  366, 374, 200, 516, 145, 364, 380, 379, 376, //
  490, 180, 397, 396, 355, 419, 334, 127, 525,
];
const _white = [
  341, 347, 168, 489, 137, 335, 347, 341, 366, //
  464, 147, 369, 373, 329, 389, 304, 109, 492,
];
const _yellow = [
  321, 329, 129, 472, 119, 316, 326, 322, 348, //
  448, 133, 323, 352, 304, 364, 291, 95, 480,
];

void main() {
  group('par recovered from yardages', () {
    test('one tee box is enough to get every hole right', () {
      final p = inferParFromYardages([_black])!;
      expect(p.pars, _realPars);
    });

    test('more tee boxes do not change the answer', () {
      expect(inferParFromYardages([_black, _white, _yellow])!.pars, _realPars);
    });

    test('the printed total confirms a guess that was already made', () {
      final p = inferParFromYardages([_black], total: _realTotal)!;
      expect(p.pars, _realPars);
      expect(p.total, _realTotal);
      // Nothing needed promoting: the guess already added up.
      expect(p.fivesNeeded, 0);
    });

    test('short holes are certain, par-4/5 overlaps are not', () {
      final p = inferParFromYardages([_black])!;
      for (final hole in [3, 5, 11, 17]) {
        expect(p.certain[hole - 1], isTrue, reason: 'hole $hole is a par 3');
        expect(p.pars[hole - 1], 3);
      }
      for (final hole in [4, 10, 18]) {
        expect(p.certain[hole - 1], isTrue, reason: 'hole $hole is a par 5');
        expect(p.pars[hole - 1], 5);
      }
      // Hole 15 measures 419 from the longest tee, which is genuinely
      // between a par 4 and a par 5, so it is asked about, not guessed.
      expect(p.uncertainHoles, [15]);
    });

    test('a damaged row cannot shift a good one', () {
      // This is what a lost digit does: every value after the gap moves one
      // hole left, so a par 3 at hole 3 votes for hole 3 with hole 4's
      // yardage. A short row must be ignored rather than trusted.
      const damaged = [
        264, 111, 407, 107, 284, 299, 291, 309, //
        382, 110, 286, 311, 269, 329, 94, 410,
      ];
      expect(inferParFromYardages([damaged]), isNull);
      expect(inferParFromYardages([_black, damaged])!.pars, _realPars);
    });

    test('a par value read off the card wins over the guess', () {
      final partial = [for (var i = 0; i < 18; i++) i < 2 ? 4 : 0];
      expect(
        inferParFromYardages([_black], partialPars: partial)!.pars,
        _realPars,
      );
    });

    test('no whole row means no guess', () {
      expect(inferParFromYardages([]), isNull);
      expect(
        inferParFromYardages([
          [100, 200, 300],
        ]),
        isNull,
      );
    });
  });

  group('printed par total', () {
    test('is read from a par row whose values were lost', () {
      // A digits-only pass turns the letters back into digits, so the total
      // at the end of the row survives even when the holes did not.
      const digitsText = '4 4 3 5 3 4 4 4 4 35 5 3 4 4 4 4 4 3 5 36 71';
      expect(printedParTotal(digitsText), 71);
    });

    test('is null when the card row is unreadable', () {
      expect(printedParTotal('(N v v v e v\n(N v e v v N'), isNull);
    });

    test('is not confused by an unrelated row', () {
      expect(printedParTotal('BLACK TEES 366 374 200'), isNull);
    });
  });

  group('merging reads of the same card', () {
    // The case that used to leave the par fields empty. A pass that read the
    // par but only one tee box, and a pass that read two tee boxes but no
    // par: scoring each read as a whole and keeping only the winner throws
    // the par away, because two tee boxes outscore one tee box plus a par.
    final withParsOnly = parseScorecardText(
      '1 2 3 4 5 6 7 8 9 OUT  10 11 12 13 14 15 16 17 18 IN TOT\n'
      'PAR ${_realPars.take(9).join(" ")} 35 ${_realPars.skip(9).join(" ")}'
      ' 36 71 - -\n'
      'BLACK TEES ${_black.join(" ")} 3100 490 180 397 396 355 419 334 '
      '127 525 3223 6323 70.4',
    );

    final withTeesOnly = parseScorecardText(
      '1 2 3 4 5 6 7 8 9 OUT  10 11 12 13 14 15 16 17 18 IN TOT\n'
      'BLACK TEES ${_black.join(" ")} 3100 490 180 397 396 355 419 334 '
      '127 525 3223 6323 70.4 -\n'
      'WHITE TEES ${_white.join(" ")} 2830 464 147 369 373 329 389 304 '
      '109 492 2701 5531 63.2 -',
    );

    test('the tee-heavy read really would have won on its own', () {
      expect(
        withTeesOnly.pars,
        isEmpty,
        reason: 'sanity: the two-tee read has no par row at all',
      );
      expect(withTeesOnly.tees.length, 2);
      expect(withParsOnly.tees.length, 1);
      expect(
        scanQuality(withTeesOnly),
        greaterThan(scanQuality(withParsOnly)),
        reason: 'this is the ranking that used to throw the par away',
      );
    });

    test('merging keeps the par that lost on its own', () {
      final merged = mergeScans([withTeesOnly, withParsOnly]);
      expect(merged.pars, _realPars);
      expect(merged.tees.map((t) => t.yards.length), [18, 18]);
      expect(merged.tees.first.yards, _black);
      expect(merged.tees.last.yards, _white);
    });

    test('order does not matter', () {
      expect(mergeScans([withParsOnly, withTeesOnly]).pars, _realPars);
    });

    test('merging one read changes nothing', () {
      expect(mergeScans([withTeesOnly]).tees, withTeesOnly.tees);
      expect(mergeScans([]).isEmpty, isTrue);
    });

    test('a verified tee beats an unverified one of the same name', () {
      // Two reads of the same black tee box, one of which dropped hole 3's
      // yardage and so renamed every hole after it. The damaged row no
      // longer adds up to the subtotals printed beside it, which is the only
      // thing that catches it, so the good read wins.
      final good = _parse(
        'BLACK TEES ${_black.join(" ")} 3100 490 180 397 396 355 419 334 '
        '127 525 3223 6323 70.4 -',
      );
      final dropped = [for (final y in _black) y]..removeAt(2);
      final bad = _parse(
        'BLACK TEES ${dropped.join(" ")} 3100 490 180 397 396 355 419 334 '
        '127 525 3223 6323 70.4 -',
      );
      expect(good.tees.first.verified, isTrue);
      expect(bad.tees.first.verified, isFalse);
      final merged = mergeScans([bad, good]);
      expect(merged.tees.length, 1);
      expect(merged.tees.first.yards, _black);
      expect(merged.tees.first.verified, isTrue);
    });

    test('par mismatch is reported against the merged par, not per pass', () {
      // The yardage read saw no par row, so it had nothing to check hole 1
      // against and reported no mismatch — an empty list that means "no
      // opinion", not "all clear". The par read then supplies a par 5 for
      // hole 1, which 366 yards cannot be, and the merged scan has to say so
      // instead of carrying the yardage read's "verified" forward.
      final yardsOnly = _parse(
        'BLACK TEES ${_black.join(" ")} 3100 490 180 397 396 355 419 334 '
        '127 525 3223 6323 70.4 -',
      );
      final parOnly = parseScorecardText(
        'PAR ${[for (var i = 0; i < 9; i++) i == 0 ? 5 : _realPars[i]].join(" ")} '
        '35 ${_realPars.skip(9).join(" ")} 36 71 - -',
      );
      expect(yardsOnly.tees.first.parMismatch, isEmpty);
      final merged = mergeScans([yardsOnly, parOnly]);
      // Hole 1 reads as a par 5 measured at 366 yards.
      expect(merged.tees.first.parMismatch, [1]);
      expect(merged.tees.first.verified, isFalse);
    });
  });

  group('the real failing scan', () {
    // Kept verbatim: the par row as letters, the header as noise, RED with
    // two lost digits, the handicap rows full of junk where the dashes were.
    late ScorecardScan scan;

    setUpAll(() {
      final text = File('test/fixtures/real_bad_scan.txt').readAsStringSync();
      scan = parseScorecardText(text);
    });

    test('still recovers the one tee box that read cleanly', () {
      final black = scan.tees.firstWhere((t) => t.yards.length == 18);
      expect(black.yards, _black);
      expect(black.verified, isTrue);
    });

    test('does not claim a damaged row is verified', () {
      final red = scan.tees.firstWhere((t) => t.yards.length < 18);
      expect(red.verified, isFalse);
    });

    test('recovers all 18 pars from the yardages alone', () {
      final p = inferParFromYardages([
        for (final t in scan.tees)
          if (t.verified) t.yards,
      ])!;
      expect(p.pars, _realPars);
      expect(p.uncertainHoles, [15]);
    });
  });
}

/// One tee-box row on a card whose header was not read. Parsed rather than
/// hand-built, so a read gets the same subtotal checking a real one gets.
ScorecardScan _parse(String row) => parseScorecardText(
  '1 2 3 4 5 6 7 8 9 OUT  10 11 12 13 14 15 16 17 18 '
  'IN TOT\n$row',
);

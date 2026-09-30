import 'package:flutter_test/flutter_test.dart';

import 'package:ghin_golf/score_entry.dart';

/// A flat par-72 layout: 4,4,3,5 x4 = 16, then 4,4,3,4 x2 = 15, 72 total.
const par72 = <int>[4, 4, 3, 5, 4, 4, 3, 5, 4, 4, 3, 5, 4, 4, 3, 5, 4, 4];

/// Front nine of [par72], par 36.
const frontNine = <int>[4, 4, 3, 5, 4, 4, 3, 5, 4];

void main() {
  group('spreadTotal', () {
    test('an even round is all pars', () {
      expect(spreadTotal(72, par72), par72);
    });

    // Assertions are about each hole relative to its own par, since a real
    // card mixes par 3s, 4s and 5s and absolute values say nothing.
    test('a four-over total is four holes at par+1, rest par', () {
      final s = spreadTotal(76, par72);
      expect(s, hasLength(18));
      expect(s.fold(0, (a, b) => a + b), 76);
      final diffs = [for (var i = 0; i < 18; i++) s[i] - par72[i]];
      expect(diffs.where((d) => d == 1), hasLength(4));
      expect(diffs.where((d) => d == 0), hasLength(14));
    });

    test('a two-under total is two holes at par-1, rest par', () {
      final s = spreadTotal(70, par72);
      expect(s.fold(0, (a, b) => a + b), 70);
      final diffs = [for (var i = 0; i < 18; i++) s[i] - par72[i]];
      expect(diffs.where((d) => d == -1), hasLength(2));
      expect(diffs.where((d) => d == 0), hasLength(16));
    });

    test('a difference wider than one stroke is shared across every hole', () {
      // +9 over 9 holes is a stroke more on all nine, not nine strokes on the
      // first hole.
      final s = spreadTotal(45, frontNine);
      expect(s.fold(0, (a, b) => a + b), 45);
      expect([
        for (var i = 0; i < 9; i++) s[i] - frontNine[i],
      ], everyElement(1));
    });

    test('round totals are exact for every offset in both directions', () {
      for (var total = 54; total <= 90; total++) {
        expect(
          spreadTotal(total, par72).fold(0, (a, b) => a + b),
          total,
          reason: 'total $total did not recombine',
        );
      }
    });

    test('an empty par list yields no scores', () {
      expect(spreadTotal(72, const []), isEmpty);
    });
  });

  group('parseRoundTotal', () {
    test('accepts a single number for 18 holes', () {
      final r = parseRoundTotal('76', par72);
      expect(r.isValid, isTrue);
      expect(r.total, 76);
      expect(r.scores, hasLength(18));
      expect(r.scores.fold(0, (a, b) => a + b), 76);
    });

    test('accepts a single number for a nine', () {
      final r = parseRoundTotal('38', frontNine);
      expect(r.isValid, isTrue);
      expect(r.scores, hasLength(9));
      expect(r.scores.fold(0, (a, b) => a + b), 38);
    });

    test('tolerates surrounding whitespace', () {
      expect(parseRoundTotal('  76  ', par72).isValid, isTrue);
    });

    test('rejects a decimal and a per-hole list', () {
      expect(parseRoundTotal('76.5', par72).message, '"76.5" is not a number');
      expect(
        parseRoundTotal('4 5 4 3', frontNine).message,
        '"4 5 4 3" is not a number',
      );
    });

    test('rejects an empty entry', () {
      expect(parseRoundTotal('', par72).message, 'Enter your total');
      expect(parseRoundTotal('   ', par72).message, 'Enter your total');
    });

    test('rejects a total that cannot be real per-hole scores', () {
      // 400 on 18 holes would need 20s everywhere.
      final r = parseRoundTotal('400', par72);
      expect(r.isValid, isFalse);
      expect(r.message, 'A total of 400 is not a score for 18 holes');
      expect(r.scores, isEmpty);
    });

    test('rejects a below-one-per-hole total', () {
      expect(parseRoundTotal('10', par72).isValid, isFalse);
    });

    test('reports a missing tee rather than inventing pars', () {
      expect(
        parseRoundTotal('76', const []).message,
        'Pick a course and tee first',
      );
    });

    test('a valid result is unmodifiable', () {
      final r = parseRoundTotal('76', par72);
      expect(() => r.scores.add(3), throwsUnsupportedError);
    });
  });

  group('labels', () {
    test('names the nine that was played', () {
      expect(nineLabel(0), 'Front 9');
      expect(nineLabel(9), 'Back 9');
    });

    test('selection label includes the nine only when it applies', () {
      expect(selectionLabel(18, 0), '18 holes');
      expect(selectionLabel(9, 0), '9 holes • Front 9');
      expect(selectionLabel(9, 9), '9 holes • Back 9');
      expect(selectionLabel(10, 0), '10 holes played');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:ghin_golf/whs.dart';

/// 380 days after the last round of the stale-window fixture, so the low
/// index that record established is more than a year behind the most recent
/// score.
final _afterTwoYears = DateTime(2022, 1, 11);

void main() {
  test('score differential matches WHS formula', () {
    // (113/133) * (85 - 72.1) = ~10.96
    final d = scoreDifferential(
      adjustedGrossScore: 85,
      courseRating: 72.1,
      slopeRating: 133,
    );
    expect(d, 11.0);
    expect(
      scoreDifferentialUnrounded(
        adjustedGrossScore: 85,
        courseRating: 72.1,
        slopeRating: 133,
      ),
      closeTo(10.96, 0.001),
    );
  });

  test('9-hole differential adds the handicap-based expected differential', () {
    expect(expectedNineHoleScoreDifferential(14), 8.48);
    expect(
      nineHoleScoreDifferential(
        adjustedGrossScore: 43,
        courseRating: 35.8,
        slopeRating: 113,
        handicapIndex: 14,
      ),
      15.7,
    );
    expect(
      nineHoleScoreDifferentialUnrounded(
        adjustedGrossScore: 43,
        courseRating: 35.8,
        slopeRating: 113,
        handicapIndex: 14,
        pcc: 2,
      ),
      closeTo(14.68, 0.001),
    );
  });

  test('net double bogey cap limits high hole scores', () {
    // Par 4, 1 stroke received -> cap = 4+2+1 = 7. Score 9 caps to 7.
    final adj = adjustedGross(
      scores: [9],
      pars: [4],
      strokeIndexes: [5],
      courseHandicap: 10, // SI 5 <= 10 -> 1 stroke
    );
    expect(adj, 7);
    expect(netDoubleBogeyCap(4, -1), 5);
    expect(netDoubleBogeyCap(4, 4, courseHandicap: 74), 9);
    expect(
      adjustedGross(
        scores: [9],
        pars: [4],
        strokeIndexes: [18],
        courseHandicap: -2,
      ),
      5,
    );
  });

  test('strokes received allocation incl. plus handicaps', () {
    expect(strokesReceived(10, 5), 1);
    expect(strokesReceived(10, 15), 0);
    expect(strokesReceived(20, 1), 2);
    expect(strokesReceived(-2, 1), 0);
    expect(strokesReceived(-2, 18), -1);
    expect(strokesReceived(-2, 17), -1);
    expect(strokesReceived(-2, 5), 0);
  });

  test('handicap index averages best 8 of 20', () {
    final diffs = List.generate(20, (i) => 10.0 + i); // 10..29
    final hi = handicapIndex(diffs);
    // best 8 = 10..17, avg = 13.5
    expect(hi, closeTo(13.5, 0.001));
  });

  test('handicap index small-field table', () {
    expect(handicapIndex([12.0, 14.0]), null); // <3 -> none
    // 3 scores: lowest 1 minus 2.0
    expect(handicapIndex([12.0, 14.0, 16.0]), closeTo(10.0, 0.001));
    // 4 scores: lowest 1 minus 1.0
    expect(handicapIndex([10.0, 12.0, 14.0, 16.0]), closeTo(9.0, 0.001));
    // 5 scores: lowest 1, no deduction
    expect(handicapIndex([10.0, 12.0, 14.0, 16.0, 18.0]), closeTo(10.0, 0.001));
    // 6 scores: lowest 2 averaged minus 1.0
    final hi6 = handicapIndex(
      [20, 19, 18, 17, 16, 15].map((e) => e.toDouble()).toList(),
    );
    expect(hi6, closeTo(14.5, 0.001));
    // 7 scores: lowest 2, no deduction
    final hi7 = handicapIndex(
      [20, 19, 18, 17, 16, 15, 14].map((e) => e.toDouble()).toList(),
    );
    expect(hi7, closeTo(14.5, 0.001));
  });

  test('handicap index has no 0.96 factor and caps at 54', () {
    // Best 8 of 10..29 averages 13.5; pre-2020 x0.96 would give ~13.0.
    final diffs = List.generate(20, (i) => 10.0 + i);
    expect(handicapIndex(diffs), closeTo(13.5, 0.001));
    expect(handicapIndex(List.filled(20, 60.0)), closeTo(54.0, 0.001));
  });

  test('course handicap and target score', () {
    final ch = courseHandicap(
      handicapIndex: 10.0,
      slopeRating: 133,
      courseRating: 72.1,
      par: 72,
    );
    expect(ch, 12); // 10*(133/113) + 0.1 = 11.87 -> 12
    expect(targetScore(72, ch), 84);
    expect(playingHandicap(12, 0.85), 10);
    expect(
      playingHandicapFromIndex(
        handicapIndex: 10,
        slopeRating: 133,
        courseRating: 72.1,
        par: 72,
        allowance: individualStrokePlayAllowance,
      ),
      11,
    );
  });

  test('nine-hole course handicap uses half the Handicap Index', () {
    expect(
      nineHoleCourseHandicap(
        handicapIndex: 14,
        slopeRating: 113,
        courseRating: 35,
        par: 36,
      ),
      6,
    );
  });

  test('nine-hole course handicap rounds half the index to a tenth first', () {
    // Rule 6.1b: the half itself is rounded to a tenth before the slope
    // applies. 13.3/2 = 6.65 -> 6.7, then 6.7 + (36.82-36) = 7.52 -> 8.
    // Without the tenth-rounding the raw 6.65 + 0.82 = 7.47 would round to 7.
    expect(
      nineHoleCourseHandicap(
        handicapIndex: 13.3,
        slopeRating: 113,
        courseRating: 36.82,
        par: 36,
      ),
      8,
    );
  });

  group('playing handicap allowances', () {
    test('single-player allowances round the unrounded Course Handicap', () {
      // CH 12.7 -> 95% = 12.065 -> 12.
      expect(playingHandicap(12.7, individualStrokePlayAllowance), 12);
      expect(playingHandicap(12.7, individualMatchPlayAllowance), 13);
      expect(playingHandicap(12.7, fourBallStrokePlayAllowance), 11);
      expect(playingHandicap(12.7, fourBallMatchPlayAllowance), 11);
      expect(playingHandicap(12.7, best1Of4Allowance), 10);
      expect(playingHandicap(12.7, best2Of4Allowance), 11);
      expect(playingHandicap(12.7, best3Of4Allowance), 13);
      expect(playingHandicap(12.7, best4Of4Allowance), 13);
    });

    test('match play walks strokes off the lowest Playing Handicap', () {
      expect(matchPlayStrokesGiven(11, 5), 6);
      expect(matchPlayStrokesGiven(5, 5), 0);
      expect(matchPlayStrokesGiven(2, -1), 3);
    });

    test('foursomes stroke play: 50% of the combined Course Handicap', () {
      // (12 + 6) / 2 = 9.
      expect(foursomesStrokePlayHandicap(12, 6), 9);
      expect(foursomesStrokePlayHandicap(13, 6), 10);
    });

    test('foursomes match play: 50% of the combined difference', () {
      // (12+6=18) vs (4+4=8): diff 10 -> 5 strokes to the higher pairing.
      expect(foursomesMatchPlayHandicap(18, 8), 5);
      expect(foursomesMatchPlayHandicap(8, 18), 5);
      expect(foursomesMatchPlayHandicap(10, 10), 0);
    });
  });

  test('yardsBetween is sane for ~100 yards', () {
    // ~0.0009 deg latitude ~= 100m ~= 109yd
    final y = yardsBetween(40.0, -105.0, 40.0009, -105.0);
    expect(y, inInclusiveRange(90, 130));
  });

  group('cap', () {
    // Five scores: the index is the best 1 (no small-record adjustment), so
    // a flat record reads straight off the differentials.
    test('no cap within 3 strokes of the low index', () {
      // Index 4.0 is exactly 3.0 above a 1.0 low index: untouched.
      expect(handicapIndex([4, 4, 4, 4, 4], lowHi: 1.0), closeTo(4.0, 0.001));
    });

    test('soft cap halves the rise past 3 strokes', () {
      // Index 5.0, low 1.0 -> rise 4.0 -> 1.0 + 3.0 + (4.0-3.0)/2 = 4.5.
      expect(handicapIndex([5, 5, 5, 5, 5], lowHi: 1.0), closeTo(4.5, 0.001));
    });

    test('hard cap holds the rise at 5 strokes', () {
      // Index 9.0, low 1.0 -> rise 8.0, past 5.0 -> capped at 6.0.
      expect(handicapIndex([9, 9, 9, 9, 9], lowHi: 1.0), closeTo(6.0, 0.001));
    });

    test('softened rise is hard-capped only above 5 strokes', () {
      expect(handicapIndex([5.625, 5.625, 5.625, 5.625, 5.625], lowHi: 0), 4.3);
      expect(handicapIndex([3.06, 3.06, 3.06, 3.06, 3.06], lowHi: 0), 3.1);
      expect(handicapIndex([7.0, 7.0, 7.0, 7.0, 7.0], lowHi: 0), 5.0);
      expect(handicapIndex([7.1, 7.1, 7.1, 7.1, 7.1], lowHi: 0), 5.0);
    });

    test('the cap only ever limits an increase', () {
      // Below the low index there is nothing to cap.
      expect(handicapIndex([0, 0, 0, 0, 0], lowHi: 5.0), closeTo(0.0, 0.001));
    });
  });

  group('handicapIndexFromRecord', () {
    /// [rounds] rounds one day apart from 2026-01-01, all [d] differential.
    List<ScoredRound> record(List<double> diffs) => [
      for (var i = 0; i < diffs.length; i++)
        ScoredRound(
          playedAt: DateTime(2026, 1, 1).add(Duration(days: i)),
          differential: diffs[i],
        ),
    ];

    test('fewer than three scores has no index', () {
      expect(handicapIndexFromRecord(record([1.0, 2.0])), isNull);
      expect(handicapIndexFromRecord(const []), isNull);
    });

    test('three nine-hole scores do not yet total 54 holes', () {
      // Rule 5.2 needs 54 holes, so three nines (27 holes) stay unindexed.
      final nines = [
        for (var i = 0; i < 3; i++)
          ScoredRound(
            playedAt: DateTime(2026, 1, 1).add(Duration(days: i)),
            differential: 10.0,
            holesPlayed: 9,
          ),
      ];
      expect(handicapIndexFromRecord(nines), isNull);
    });

    test('six nine-hole scores establish an index', () {
      final nines = [
        for (var i = 0; i < 6; i++)
          ScoredRound(
            playedAt: DateTime(2026, 1, 1).add(Duration(days: i)),
            differential: 10.0,
            holesPlayed: 9,
          ),
      ];
      // 6 scores -> best 2, minus the 6-score adjustment of 1.0.
      expect(handicapIndexFromRecord(nines), closeTo(9.0, 0.001));
    });

    test('a short record is never capped', () {
      // One great round and five bad ones. The lowest differential (-10.0) is
      // not a low handicap index — no index exists below 20 scores — so the
      // average stands: best 2 of -10/10x5 is 0.0, less the 6-score
      // adjustment of 1.0.
      expect(
        handicapIndexFromRecord(record([-10, 10, 10, 10, 10, 10])),
        closeTo(-1.0, 0.001),
      );
    });

    test('a single low differential does not pin the index for good', () {
      // The same shape with 20 scores behind it. Nothing here rises 3 strokes
      // above a low index built from 5.0s, so the index is the plain 5.0.
      final diffs = [for (var i = 0; i < 20; i++) 5.0];
      expect(handicapIndexFromRecord(record(diffs)), closeTo(5.0, 0.001));
    });

    test('a bad run softens before reaching the hard cap', () {
      // 20 rounds at exactly their expected score set a low index of 0.0.
      // The 5.625 rise is softened to 4.3125, then rounded to 4.3.
      final diffs =
          [for (var i = 0; i < 20; i++) 0.0] +
          [for (var i = 0; i < 13; i++) 45.0];
      expect(handicapIndexFromRecord(record(diffs)), closeTo(4.3, 0.001));
    });

    test('a mild bad run only meets the soft cap', () {
      // 20 rounds at 0.0, then 13 at 30.0: 8-of-20 = 30/8 = 3.75 above the
      // low index, so the soft cap gives 3.0 + 0.75/2 = 3.375 -> 3.4.
      final diffs =
          [for (var i = 0; i < 20; i++) 0.0] +
          [for (var i = 0; i < 13; i++) 30.0];
      expect(handicapIndexFromRecord(record(diffs)), closeTo(3.4, 0.001));
    });

    test('a previously established low still caps the next score', () {
      // Twenty good rounds and twelve bad rounds leave a 0.0 index on the
      // previous score. Although that Low Index is now 380 days old, it still
      // applies to the score being processed; the rolling window refreshes
      // only after the score has been capped.
      final rounds = [
        for (var i = 0; i < 20; i++)
          ScoredRound(
            playedAt: DateTime(2020, 1, 1).add(Duration(days: i)),
            differential: 0.0,
          ),
        for (var i = 0; i < 12; i++)
          ScoredRound(
            playedAt: DateTime(2020, 2, 1).add(Duration(days: 30 * i)),
            differential: 45.0,
          ),
        ScoredRound(playedAt: _afterTwoYears, differential: 45.0),
      ];
      // The previous score still had a 0.0 Low Index, so the 5.625 rise is
      // softened to 4.3.
      expect(handicapIndexFromRecord(rounds), closeTo(4.3, 0.001));
    });

    test('order of the input does not matter', () {
      final diffs =
          [for (var i = 0; i < 20; i++) 5.0] +
          [for (var i = 0; i < 13; i++) 45.0];
      final forwards = record(diffs);
      final backwards = record(diffs).reversed.toList();
      expect(
        handicapIndexFromRecord(forwards),
        closeTo(handicapIndexFromRecord(backwards)!, 0.001),
      );
    });

    test('agrees with the plain index when the record is under 20', () {
      final diffs = [3.0, 9.0, 12.0, 6.0, 4.0, 15.0, 7.0];
      expect(
        handicapIndexFromRecord(record(diffs)),
        closeTo(handicapIndex(diffs)!, 0.001),
      );
    });

    test(
      'exceptional reductions apply to the current twenty differentials',
      () {
        final rounds = [
          for (var i = 0; i < 20; i++)
            ScoredRound(
              playedAt: DateTime(2026, 1, 1).add(Duration(days: i)),
              differential: 15,
              unroundedDifferential: 15,
              handicapIndexAtPlay: 15,
            ),
          ScoredRound(
            playedAt: DateTime(2026, 1, 21),
            differential: 5,
            unroundedDifferential: 5,
            handicapIndexAtPlay: 15,
          ),
        ];
        expect(handicapIndexFromRecord(rounds), 11.8);
      },
    );

    test(
      'exceptional reductions stack and expire with their affected scores',
      () {
        final rounds = [
          for (var i = 0; i < 20; i++)
            ScoredRound(
              playedAt: DateTime(2026, 1, 1).add(Duration(days: i)),
              differential: 15,
              unroundedDifferential: 15,
              handicapIndexAtPlay: 15,
            ),
          for (var i = 0; i < 2; i++)
            ScoredRound(
              playedAt: DateTime(2026, 1, 21).add(Duration(days: i)),
              differential: 5,
              unroundedDifferential: 5,
              handicapIndexAtPlay: 15,
            ),
        ];
        expect(handicapIndexFromRecord(rounds), 8.8);
      },
    );
  });

  test('exceptional score thresholds use the unrounded differential', () {
    expect(exceptionalScoreReduction(8.0, 15.0), 1.0);
    expect(exceptionalScoreReduction(5.0, 15.0), 2.0);
    // Rounding cannot push a raw differential into the exceptional band.
    expect(exceptionalScoreReduction(8.05, 15.0), 0.0);
  });
}

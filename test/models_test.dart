import 'package:flutter_test/flutter_test.dart';

import 'package:ghin_golf/models.dart';
import 'package:ghin_golf/store.dart';

void main() {
  test('putts are always less than the total score', () {
    final h = HoleScore(score: 4, putts: 6);
    h.sanitize();
    expect(h.score, 4);
    expect(h.putts, 3);
    final ace = HoleScore(score: 1, putts: 1);
    ace.sanitize();
    expect(ace.putts, 0);
  });

  test('penalties leave at least one non-penalty stroke', () {
    final h = HoleScore(score: 3, putts: 2, penalties: 4);
    h.sanitize();
    expect(h.score, 3);
    expect(h.penalties, 2);
    final ace = HoleScore(score: 1, penalties: 1);
    ace.sanitize();
    expect(ace.penalties, 0);
  });

  test('gir is user-entered, defaulting to false', () {
    expect(HoleScore(score: 4).gir, false);
    final h = HoleScore(score: 4, gir: true);
    final back = HoleScore.fromJson(h.toJson());
    expect(back.gir, true);
    // Old saves without the field load as false.
    final legacy = HoleScore.fromJson({'score': 4});
    expect(legacy.gir, false);
  });

  test('score bounds are enforced', () {
    final h = HoleScore(score: 0, putts: -1, penalties: -2);
    h.sanitize();
    expect(h.score, 1);
    expect(h.putts, 0);
    expect(h.penalties, 0);
  });

  group('pendingSync', () {
    // There is no remote backend (no accounts, no API): a posted
    // round is complete the moment it is saved, so nothing is ever
    // left in a "syncing" state. A round that stayed true forever
    // would keep the Home counter reading "N syncing" permanently.
    test('a new round is complete, not pending', () {
      expect(
        Round(
          id: 'r',
          courseId: 'c',
          teeId: 't',
          playedAt: DateTime.now(),
          holes: const [],
        ).pendingSync,
        isFalse,
      );
    });

    test('survives a save/load round trip as complete', () {
      final r = Round(
        id: 'r',
        courseId: 'c',
        teeId: 't',
        playedAt: DateTime(2026, 1, 1),
        holes: List.generate(18, (i) => HoleScore(score: 4)),
      );
      expect(r.pendingSync, isFalse);
      final back = Round.fromJson(r.toJson());
      expect(back.pendingSync, isFalse);
    });
  });

  group('course scan text', () {
    final course = Course(
      id: 'c1',
      name: 'Test Course',
      city: 'Somewhere',
      state: 'IL',
      tees: const [],
      custom: true,
      imagePath: '/tmp/card.jpg',
      ocrText: 'PAR 4 4 3\nBLACK 366 374 200',
    );

    test('survives a save/load round trip', () {
      final back = Course.fromJson(course.toJson());
      expect(back.ocrText, course.ocrText);
      expect(back.imagePath, '/tmp/card.jpg');
    });

    test('defaults to empty so hand-typed courses are unaffected', () {
      final plain = Course(
        id: 'c2',
        name: 'Plain',
        city: '',
        state: '',
        tees: const [],
      );
      expect(plain.ocrText, isEmpty);
      expect(plain.ocrAttempts, isEmpty);
    });

    test('loads courses saved before the field existed', () {
      // Old saved JSON has no ocrText key at all; reading it must not throw.
      final old = Course.fromJson({
        'id': 'c3',
        'name': 'Old',
        'tees': <dynamic>[],
      });
      expect(old.ocrText, isEmpty);
      expect(old.ocrAttempts, isEmpty);
    });
  });

  group('which nine was played', () {
    // Pars differ across the tee, so pairing a back-nine scorecard with the
    // front nine's pars would report the wrong score-to-par and freeze the
    // wrong course handicap onto the round.
    final tee = Tee(
      id: 't',
      name: 'Test',
      rating: 70,
      slope: 130,
      holes: [
        for (var i = 0; i < 18; i++)
          HoleInfo(
            number: i + 1,
            par: i < 9 ? 4 : 5, // front nine all par 4, back nine all par 5
            yardage: 400,
            strokeIndex: i + 1,
          ),
      ],
    );

    Round nine({required int startHole}) => Round(
      id: 'r',
      courseId: 'c',
      teeId: 't',
      playedAt: DateTime(2026, 1, 1),
      holes: List.generate(9, (i) => HoleScore(score: 4)),
      startHole: startHole,
    );

    Round eighteen() => Round(
      id: 'r',
      courseId: 'c',
      teeId: 't',
      playedAt: DateTime(2026, 1, 1),
      holes: List.generate(18, (i) => HoleScore(score: 4)),
    );

    test('pars come from the nine that was played', () {
      expect(nine(startHole: 0).parsOn(tee), List.filled(9, 4));
      expect(nine(startHole: 9).parsOn(tee), List.filled(9, 5));
    });

    test('par played sums the played nine, not the whole tee', () {
      expect(nine(startHole: 0).parPlayed(tee), 36);
      expect(nine(startHole: 9).parPlayed(tee), 45);
      expect(nine(startHole: 0).courseHandicap, isNull);
      expect(nine(startHole: 0).adjustedGrossFor(tee), isNull);
    });

    test('an 18-hole round reads the whole tee', () {
      expect(eighteen().parPlayed(tee), 81);
      expect(eighteen().isBackNine, isFalse);
    });

    test('only a nine starting at 10 counts as the back nine', () {
      expect(nine(startHole: 9).isBackNine, isTrue);
      expect(nine(startHole: 0).isBackNine, isFalse);
      // An 18-hole round is not a "back nine" even though it covers those holes.
      expect(eighteen().isBackNine, isFalse);
    });

    test('a tee too short for the round yields null, not invented par', () {
      final short = Tee(
        id: 's',
        name: 'Nine',
        rating: 70,
        slope: 130,
        holes: tee.holes.take(9).toList(),
      );
      expect(nine(startHole: 9).parsOn(short), isNull);
      expect(nine(startHole: 9).parPlayed(short), isNull);
    });

    test('the played nine survives a save/load round trip', () {
      final back = Round.fromJson(nine(startHole: 9).toJson());
      expect(back.startHole, 9);
      expect(back.isBackNine, isTrue);
      expect(back.parPlayed(tee), 45);
      expect(back.differential(tee), isNull);
    });

    test(
      'eligible partial 18-hole scores use expected unplayed-hole scores',
      () {
        final courseTee = Tee(
          id: 'full',
          name: 'Full',
          rating: 72,
          slope: 113,
          holes: [
            for (var i = 0; i < 18; i++)
              HoleInfo(number: i + 1, par: 4, yardage: 400, strokeIndex: i + 1),
          ],
        );
        final partial = Round(
          id: 'partial',
          courseId: 'c',
          teeId: 'full',
          playedAt: DateTime(2026, 1, 1),
          holes: List.generate(10, (_) => HoleScore(score: 4)),
          courseHandicap: 10,
          handicapIndexAtPlay: 10,
          incompleteRoundReasonValid: true,
        );
        expect(partial.adjustedGrossFor(courseTee), 40);
        expect(partial.differential(courseTee), 4.4);
      },
    );

    test('partial round without a valid reason is not handicap acceptable', () {
      final partial = Round(
        id: 'partial',
        courseId: 'c',
        teeId: 't',
        playedAt: DateTime(2026, 1, 1),
        holes: List.generate(10, (_) => HoleScore(score: 4)),
        courseHandicap: 10,
        handicapIndexAtPlay: 10,
      );
      expect(partial.differential(tee), isNull);
    });

    test('a round before a Handicap Index uses par plus five', () {
      final noIndex = Round(
        id: 'no-index',
        courseId: 'c',
        teeId: 't',
        playedAt: DateTime(2026, 1, 1),
        holes: List.generate(18, (_) => HoleScore(score: 12)),
      );
      expect(noIndex.adjustedGrossFor(tee), tee.par + 90);
    });

    test('missing and explicitly zero index snapshots remain distinct', () {
      final base = {
        'id': 'legacy',
        'courseId': 'c',
        'teeId': 't',
        'playedAt': '2026-01-01T00:00:00.000',
        'holes': <dynamic>[],
      };
      expect(Round.fromJson(base).handicapIndexAtPlay, isNull);
      expect(
        Round.fromJson({
          ...base,
          'handicapIndexAtPlay': 0.0,
        }).handicapIndexAtPlay,
        0.0,
      );
    });

    test(
      'rounds saved before the back nine existed load as the front nine',
      () {
        final legacy = Round.fromJson({
          'id': 'r',
          'courseId': 'c',
          'teeId': 't',
          'playedAt': '2026-01-01T00:00:00.000',
          'holes': [
            for (var i = 0; i < 9; i++) {'score': 4},
          ],
        });
        expect(legacy.startHole, 0);
        expect(legacy.isBackNine, isFalse);
      },
    );
  });

  group('Tee.parsFrom', () {
    test('pads a short tee with par 4 instead of throwing', () {
      final nine = Tee(
        id: 'n',
        name: 'Nine',
        rating: 70,
        slope: 130,
        holes: [HoleInfo(number: 1, par: 3, yardage: 300, strokeIndex: 1)],
      );
      expect(nine.parsFrom(0, 3), [3, 4, 4]);
      expect(nine.parTotalFrom(0, 3), 11);
    });

    test('an 18-hole tee splits into two nines that sum to its par', () {
      final t = GolfStore().courses.first.tees.first;
      expect(t.parTotalFrom(0, 9) + t.parTotalFrom(9, 9), t.par);
    });
  });
}

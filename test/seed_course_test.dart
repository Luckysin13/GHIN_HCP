// The bundled course is a hand transcription of a real scorecard, so this
// checks it against that file rather than against itself. A wrong digit here
// would quietly skew a handicap index, and nothing else in the app would
// notice.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghin_golf/data.dart';
import 'package:ghin_golf/models.dart';
import 'package:ghin_golf/scorecard_scan.dart';

void main() {
  final source = File('/home/jonathan/CrystalLakeGolfClub.txt');

  test('bundled Crystal Lake tees include published nine-hole ratings', () {
    final expected = {
      'Black': (34.8, 129, 35.6, 128),
      'Combo': (34.3, 126, 35.1, 126),
      'White': (33.8, 125, 34.5, 123),
      'Yellow': (32.9, 122, 33.6, 121),
      'Red': (31.5, 115, 32.1, 113),
    };

    for (final tee in crystalLake.tees) {
      final (frontRating, frontSlope, backRating, backSlope) =
          expected[tee.name]!;
      expect(tee.frontNineRating, frontRating, reason: '${tee.name} front');
      expect(tee.frontNineSlope, frontSlope, reason: '${tee.name} front');
      expect(tee.backNineRating, backRating, reason: '${tee.name} back');
      expect(tee.backNineSlope, backSlope, reason: '${tee.name} back');
    }
  });

  group(
    'Crystal Lake is the only bundled course',
    () {
      test('and it is the one on disk', () {
        expect(seedCourses().length, 1);
        expect(seedCourses().single.name, 'Crystal Lake Golf Club');
      });

      test('and the store starts with it and nothing else', () {
        // Covered again in course_test.dart; repeated here so a failure points
        // at the seed data rather than at the store.
        expect(seedCourses().single.id, 'crystal-lake');
      });

      test('is not treated as a user course', () {
        // custom: true would make the course editable from its name and write
        // it into the user's saved file.
        expect(crystalLake.custom, isFalse);
      });
    },
    skip: !source.existsSync() ? 'scorecard source not present' : null,
  );

  group(
    'transcribed from the card',
    () {
      late ScorecardScan card;

      setUpAll(() {
        card = parseScorecardText(source.readAsStringSync());
      });

      test('all five tee boxes came across', () {
        expect(crystalLake.tees.length, 5);
        expect(crystalLake.tees.map((t) => t.name), [
          'Black',
          'Combo',
          'White',
          'Yellow',
          'Red',
        ]);
      });

      test('every yardage matches the card, hole for hole', () {
        for (final tee in crystalLake.tees) {
          final scanned = card.tees.firstWhere(
            (t) => t.name.toLowerCase() == tee.name.toLowerCase(),
          );
          expect(
            scanned.yards,
            tee.holes.map((h) => h.yardage).toList(),
            reason: '${tee.name} yardages',
          );
          expect(
            scanned.verified,
            isTrue,
            reason: '${tee.name} row must satisfy the card\'s own subtotals',
          );
        }
      });

      test('par matches the card, and totals 71', () {
        final onCard = <int>[];
        for (final h in crystalLake.tees.first.holes) {
          onCard.add(h.par);
        }
        expect(onCard, card.pars);
        expect(onCard.fold(0, (a, b) => a + b), 71);
        expect(crystalLake.tees.first.par, 71);
      });

      test("the handicap row is the card's men's row", () {
        expect(
          crystalLake.tees.first.holes.map((h) => h.strokeIndex).toList(),
          card.hcp,
        );
        // A stroke index is a permutation of 1..18, each hole ranked once.
        final idx =
            crystalLake.tees.first.holes.map((h) => h.strokeIndex).toList()
              ..sort();
        expect(idx, List.generate(18, (i) => i + 1));
      });

      test('ratings match the card', () {
        for (final tee in crystalLake.tees) {
          final scanned = card.tees.firstWhere(
            (t) => t.name.toLowerCase() == tee.name.toLowerCase(),
          );
          expect(scanned.rating, tee.rating, reason: '${tee.name} rating');
        }
      });

      test('yardage totals match the card\'s printed TOT column', () {
        // The card prints OUT/IN/TOT per tee; the model sums the holes, and the
        // two have to agree or a stroke total would be off.
        const printedTotals = {
          'Black': 6323,
          'Combo': 6077,
          'White': 5847,
          'Yellow': 5472,
          'Red': 4805,
        };
        for (final tee in crystalLake.tees) {
          expect(
            tee.yardage,
            printedTotals[tee.name],
            reason: '${tee.name} total',
          );
        }
      });
    },
    skip: !source.existsSync() ? 'scorecard source not present' : null,
  );

  group('slope, which the card does not print', () {
    test('runs from the longest tee to the shortest', () {
      final slopes = crystalLake.tees.map((t) => t.slope).toList();
      expect(slopes.first, greaterThan(slopes.last));
      for (var i = 1; i < slopes.length; i++) {
        expect(slopes[i - 1], greaterThan(slopes[i]));
      }
    });

    test('is plausible, and never zero', () {
      for (final tee in crystalLake.tees) {
        expect(tee.slope, inInclusiveRange(55, 155));
      }
    });

    test('spans about 26 points end to end', () {
      final spread = crystalLake.tees.first.slope - crystalLake.tees.last.slope;
      expect(spread, inInclusiveRange(20, 30));
    });
  });

  group('default tee', () {
    test('is White where the course has one', () {
      expect(crystalLake.tees.first.name, 'Black');
      expect(crystalLake.defaultTee.name, 'White');
    });

    test('matches the White name whatever its case or spacing', () {
      final odd = Course(
        id: 'odd',
        name: 'Odd',
        city: '',
        state: '',
        tees: [
          Tee(
            id: 'a',
            name: 'Championship',
            rating: 73,
            slope: 140,
            holes: crystalLake.tees.first.holes,
          ),
          Tee(
            id: 'b',
            name: ' white ',
            rating: 68,
            slope: 120,
            holes: crystalLake.tees.first.holes,
          ),
        ],
      );
      expect(odd.defaultTee.id, 'b');
    });

    test('picks the first White when a course lists two', () {
      final twin = Course(
        id: 'twin',
        name: 'Twin',
        city: '',
        state: '',
        tees: [
          Tee(
            id: 'w1',
            name: 'White',
            rating: 70,
            slope: 130,
            holes: crystalLake.tees.first.holes,
          ),
          Tee(
            id: 'b1',
            name: 'Blue',
            rating: 71,
            slope: 133,
            holes: crystalLake.tees.first.holes,
          ),
          Tee(
            id: 'w2',
            name: 'WHITE',
            rating: 69,
            slope: 127,
            holes: crystalLake.tees.first.holes,
          ),
        ],
      );
      expect(twin.defaultTee.id, 'w1');
    });

    test('falls back to the second tee when there is no White', () {
      final odd = Course(
        id: 'odd',
        name: 'Odd',
        city: '',
        state: '',
        tees: [
          Tee(
            id: 'a',
            name: 'Championship',
            rating: 73,
            slope: 140,
            holes: crystalLake.tees.first.holes,
          ),
          Tee(
            id: 'b',
            name: 'Members',
            rating: 71,
            slope: 130,
            holes: crystalLake.tees.first.holes,
          ),
          Tee(
            id: 'c',
            name: 'Ladies Forward',
            rating: 68,
            slope: 120,
            holes: crystalLake.tees.first.holes,
          ),
        ],
      );
      expect(odd.defaultTee.name, 'Members');
    });

    test('a course with a single tee gets that tee', () {
      final single = Course(
        id: 'single',
        name: 'Single',
        city: '',
        state: '',
        tees: [
          Tee(
            id: 'only',
            name: 'Championship',
            rating: 73,
            slope: 140,
            holes: crystalLake.tees.first.holes,
          ),
        ],
      );
      expect(single.defaultTee.name, 'Championship');
    });

    test('a course with no tees is a hard error, not a silent crash', () {
      final none = Course(
        id: 'none',
        name: 'None',
        city: '',
        state: '',
        tees: const [],
      );
      expect(() => none.defaultTee, throwsStateError);
    });

    test('survives a round trip through JSON', () {
      final restored = Course.fromJson(crystalLake.toJson());
      expect(restored.defaultTee.name, crystalLake.defaultTee.name);
    });
  });
}

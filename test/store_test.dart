import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ghin_golf/models.dart';
import 'package:ghin_golf/store.dart';

void main() {
  test(
    'load adds missing Crystal Lake nine ratings to saved course edits',
    () async {
      final dir = await Directory.systemTemp.createTemp('ghin-crystal-ratings');
      try {
        final original = GolfStore().courseById('crystal-lake')!;
        final teeJson = original.defaultTee.toJson()
          ..['frontNineRating'] = 36.1
          ..['frontNineSlope'] = 120
          ..['backNineRating'] = null
          ..['backNineSlope'] = null;
        final savedCourse = Course(
          id: original.id,
          name: 'My Crystal Lake',
          city: 'Lakeville',
          state: 'MN',
          custom: false,
          tees: [
            Tee.fromJson(teeJson),
            for (final tee in original.tees.skip(1))
              Tee.fromJson(
                tee.toJson()
                  ..['frontNineRating'] = null
                  ..['frontNineSlope'] = null
                  ..['backNineRating'] = null
                  ..['backNineSlope'] = null,
              ),
          ],
        );
        final file = File('${dir.path}/store.json');
        await file.writeAsString(
          jsonEncode({
            'rounds': [],
            'customCourses': [savedCourse.toJson()],
          }),
        );

        final store = GolfStore(filePath: file.path);
        await store.load();

        final loaded = store.courseById('crystal-lake')!;
        expect(loaded.name, 'My Crystal Lake');
        expect(loaded.city, 'Lakeville');
        expect(loaded.defaultTee.frontNineRating, 36.1);
        expect(loaded.defaultTee.frontNineSlope, 120);
        expect(loaded.defaultTee.backNineRating, 34.5);
        expect(loaded.defaultTee.backNineSlope, 123);
        expect(loaded.tees[1].frontNineRating, 34.3);
        expect(loaded.tees[1].frontNineSlope, 126);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  test('alphabetical course list sorts names without reordering the store', () {
    final store = GolfStore();
    final tee = store.courses.first.defaultTee;
    Course course(String id, String name, {String state = ''}) =>
        Course(id: id, name: name, city: '', state: state, tees: [tee]);
    store.courses = [
      course('z', 'zeta'),
      course('a-mn', 'Alpha', state: 'MN'),
      course('m', 'Middle'),
      course('a-wi', 'alpha', state: 'WI'),
    ];

    expect(store.alphabeticalCourses.map((course) => course.id), [
      'a-mn',
      'a-wi',
      'm',
      'z',
    ]);
    expect(store.courses.map((course) => course.id), [
      'z',
      'a-mn',
      'm',
      'a-wi',
    ]);
  });

  test('same-day rounds use the index from before that date', () {
    final store = GolfStore();
    final course = store.courses.first;
    final tee = course.tees.first;

    Round roundAt(DateTime day, {int score = 4}) => Round(
      id: day.microsecondsSinceEpoch.toString(),
      courseId: course.id,
      teeId: tee.id,
      playedAt: day,
      courseHandicap: 0,
      handicapIndexAtPlay: 40,
      holes: List.generate(tee.holes.length, (_) => HoleScore(score: score)),
    );

    for (var day = 1; day <= 3; day++) {
      store.addRound(roundAt(DateTime(2026, 1, day), score: 6));
    }
    final date = DateTime(2026, 1, 4);
    final beforeDay = store.handicapIndexBefore(date);
    expect(beforeDay, isNotNull);
    store.addRound(roundAt(date, score: 4));
    store.addRound(roundAt(date.add(const Duration(hours: 5)), score: 4));
    expect(store.handicapIndexBefore(date), beforeDay);
  });

  test('a rated nine-hole score enters the handicap record', () async {
    final dir = await Directory.systemTemp.createTemp('ghin-nine-hole-index');
    final store = GolfStore(filePath: '${dir.path}/store.json');
    final tee = Tee(
      id: 'rated-tee',
      name: 'Rated',
      rating: 70,
      slope: 113,
      frontNineRating: 35,
      frontNineSlope: 113,
      backNineRating: 35.5,
      backNineSlope: 120,
      holes: [
        for (var i = 0; i < 18; i++)
          HoleInfo(number: i + 1, par: 4, yardage: 400, strokeIndex: i + 1),
      ],
    );
    final course = Course(
      id: 'nine-hole-index-course',
      name: 'Nine Hole Index Course',
      city: '',
      state: '',
      custom: true,
      tees: [tee],
    );
    store.addCourse(course);
    Round fullRound(int day) => Round(
      id: 'full-$day',
      courseId: course.id,
      teeId: tee.id,
      playedAt: DateTime(2026, 1, day),
      holes: List.generate(18, (_) => HoleScore(score: 4)),
      courseHandicap: 0,
    );

    try {
      for (var day = 1; day <= 3; day++) {
        store.addRound(fullRound(day));
      }
      final index = store.handicapIndexBefore(DateTime(2026, 1, 4));
      expect(index, 0);

      final nine = Round(
        id: 'nine-4',
        courseId: course.id,
        teeId: tee.id,
        playedAt: DateTime(2026, 1, 4),
        holes: List.generate(9, (_) => HoleScore(score: 4)),
        courseHandicap: tee.courseHandicapForRound(
          holesPlayed: 9,
          startHole: 0,
          handicapIndex: index!,
        ),
        handicapIndexAtPlay: index,
      );
      expect(nine.differential(tee), 2.2);
      store.addRound(nine);
      await store.save();
      expect(store.handicapIndex, 1);
    } finally {
      await store.save();
      store.dispose();
      await dir.delete(recursive: true);
    }
  });

  test('seven nine-hole rounds bootstrap an index without prior snapshots', () {
    final store = GolfStore();
    final tee = store
        .courseById('crystal-lake')!
        .tees
        .firstWhere((tee) => tee.name == 'White');
    for (var day = 1; day <= 7; day++) {
      final startHole = day.isEven ? 9 : 0;
      final pars = tee.parsFrom(startHole, 9);
      store.addRound(
        Round(
          id: 'initial-nine-$day',
          courseId: 'crystal-lake',
          teeId: tee.id,
          playedAt: DateTime(2026, 2, day),
          startHole: startHole,
          holes: [for (final par in pars) HoleScore(score: par + 1)],
        ),
      );
    }

    final index = store.handicapIndex;
    expect(index, isNotNull);
    expect(index!, greaterThanOrEqualTo(0));
    expect(index, lessThanOrEqualTo(54));

    final eighthPlayedAt = DateTime(2026, 2, 8);
    final priorIndex = store.handicapIndexBefore(eighthPlayedAt);
    expect(priorIndex, isNotNull);
    final eighth = Round(
      id: 'initial-nine-8',
      courseId: 'crystal-lake',
      teeId: tee.id,
      playedAt: eighthPlayedAt,
      holes: [for (final par in tee.parsFrom(0, 9)) HoleScore(score: par + 1)],
      handicapIndexAtPlay: priorIndex,
      courseHandicap: tee.courseHandicapForRound(
        holesPlayed: 9,
        startHole: 0,
        handicapIndex: priorIndex!,
      ),
    );
    expect(eighth.differential(tee), isNotNull);
    store.addRound(eighth);
    expect(store.handicapIndex, isNotNull);
  });

  test('no Index until at least 54 holes are posted (Rule 5.2)', () {
    final store = GolfStore();
    final tee = store.courseById('crystal-lake')!.defaultTee;
    Round full(int day) => Round(
      id: 'full-$day',
      courseId: 'crystal-lake',
      teeId: tee.id,
      playedAt: DateTime(2026, 3, day),
      holes: List.generate(18, (_) => HoleScore(score: 4)),
    );
    Round nine(int day) => Round(
      id: 'nine-$day',
      courseId: 'crystal-lake',
      teeId: tee.id,
      playedAt: DateTime(2026, 3, day),
      startHole: 0,
      holes: List.generate(9, (_) => HoleScore(score: 4)),
    );

    // 18 + 18 + 9 = 45 holes: three rounds, but short of the 54-hole minimum.
    store.addRound(full(1));
    store.addRound(full(2));
    store.addRound(nine(3));
    expect(store.handicapIndex, isNull);

    // The fourth round brings it to exactly 54 and an Index appears.
    store.addRound(nine(4));
    expect(store.handicapIndex, isNotNull);
  });

  test('score colors default to the built-in palette', () {
    final s = GolfStore();
    expect(s.scoreColorValue(-2), 0xFF1B5E20);
    expect(s.scoreColorValue(0), 0xFF607D8B);
    expect(s.scoreColorValue(1), 0xFFF9A825);
    expect(s.scoreColorValue(3), 0xFFD32F2F);
  });

  test('score color diffs clamp to -2..3', () {
    final s = GolfStore();
    expect(s.scoreColorValue(-9), s.scoreColorValue(-2));
    expect(s.scoreColorValue(9), s.scoreColorValue(3));
  });

  test('decodeScoreColors falls back per entry, never throws', () {
    expect(decodeScoreColors(null), defaultScoreColors);
    expect(decodeScoreColors('nope'), defaultScoreColors);
    final d = decodeScoreColors({'-1': 0xFF0000FF, '9': 1, 'x': 'y'});
    expect(d[-1], 0xFF0000FF);
    expect(d.containsKey(9), isFalse);
    expect(d[0], defaultScoreColors[0]);
    expect(encodeScoreColors(d)['-1'], 0xFF0000FF);
  });

  test('custom score colors persist across save/load', () async {
    final dir = await Directory.systemTemp.createTemp('ghin-colors');
    final path = '${dir.path}/store.json';
    try {
      final s = GolfStore(filePath: path);
      s.setScoreColor(-1, 0xFF0000FF);
      s.setScoreColor(3, 0xFF123456);
      await s.save();
      final s2 = GolfStore(filePath: path);
      await s2.load();
      expect(s2.scoreColorValue(-1), 0xFF0000FF);
      expect(s2.scoreColorValue(3), 0xFF123456);
      expect(s2.scoreColorValue(0), defaultScoreColors[0]);
      s2.resetScoreColors();
      expect(s2.scoreColorValue(-1), defaultScoreColors[-1]);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  group('persistence', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('ghin-store');
      GolfStore.testFilePath = '${dir.path}/store.json';
    });

    tearDown(() async {
      GolfStore.testFilePath = null;
      await dir.delete(recursive: true);
    });

    Round roundAt(String id, DateTime at) => Round(
      id: id,
      courseId: 'crystal-lake',
      teeId: 'crystal-lake-white',
      playedAt: at,
      holes: List.generate(18, (i) => HoleScore(score: 4, putts: 2)),
    );

    test('a save lands whole, with no temp file left behind', () async {
      final s = GolfStore();
      s.addRound(roundAt('r1', DateTime(2026, 1, 1)));
      s.addRound(roundAt('r2', DateTime(2026, 1, 8)));
      await s.save();

      // The payload is written beside the target and renamed over it, so the
      // save file is never truncated in place.
      final onDisk = File('${dir.path}/store.json').readAsStringSync();
      expect((json.decode(onDisk) as Map)['rounds'], hasLength(2));
      final leftovers = dir
          .listSync()
          .map((e) => e.path)
          .where((p) => p.endsWith('.tmp'))
          .toList();
      expect(leftovers, isEmpty);
    });

    test(
      'edited seeded course survives save and reload without duplication',
      () async {
        final store = GolfStore();
        final original = store.courseById('crystal-lake')!;
        final tee = original.defaultTee;
        final updated = Course(
          id: original.id,
          name: 'Crystal Lake Updated',
          city: original.city,
          state: original.state,
          custom: false,
          tees: [
            Tee(
              id: tee.id,
              name: tee.name,
              rating: tee.rating,
              slope: tee.slope,
              frontNineRating: 35.1,
              frontNineSlope: 121,
              backNineRating: 35.4,
              backNineSlope: 124,
              holes: tee.holes,
            ),
            ...original.tees.skip(1),
          ],
        );
        store.updateCourse(updated);
        await store.save();

        final reloaded = GolfStore();
        await reloaded.load();
        expect(
          reloaded.courses.where((course) => course.id == original.id),
          hasLength(1),
        );
        final saved = reloaded.courseById(original.id)!;
        expect(saved.name, 'Crystal Lake Updated');
        expect(saved.custom, isFalse);
        expect(saved.defaultTee.frontNineRating, 35.1);
        expect(saved.defaultTee.frontNineSlope, 121);
        expect(saved.defaultTee.backNineRating, 35.4);
        expect(saved.defaultTee.backNineSlope, 124);
      },
    );

    test('an unreadable save file is kept, not overwritten', () async {
      final path = '${dir.path}/store.json';
      File(path).writeAsString('{"rounds": [ this is not json');
      final s = GolfStore();
      await s.load(); // must not throw
      expect(s.rounds, isEmpty);

      final kept = dir
          .listSync()
          .map((e) => e.path)
          .where((p) => p.contains('corrupt'))
          .toList();
      expect(kept, hasLength(1));
      expect(
        File(kept.single).readAsStringSync(),
        contains('this is not json'),
      );
    });

    test('saving still works after a bad load', () async {
      // Reads are chained off the last write, so a write that fails must not
      // wedge the queue and leave the store unable to save again.
      File('${dir.path}/store.json').writeAsString('not json at all');
      final s = GolfStore();
      await s.load();
      s.addRound(roundAt('r1', DateTime(2026, 1, 1)));
      await s.save();

      final s2 = GolfStore();
      await s2.load();
      expect(s2.rounds.length, 1);
    });

    test('save failures are surfaced instead of silently swallowed', () async {
      final s = GolfStore(filePath: '${dir.path}/missing/dir/store.json');
      await s.save();

      expect(s.lastSaveError, isNotNull);
      expect(s.hasSaveError, isTrue);
      expect(s.lastSaveError.toString(), contains('No such file or directory'));
    });
  });
}

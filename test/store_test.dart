import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ghin_golf/models.dart';
import 'package:ghin_golf/store.dart';

void main() {
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

  test('score colors default to the built-in palette', () {
    final s = GolfStore();
    expect(s.scoreColorValue(-2), 0xFF1B5E20);
    expect(s.scoreColorValue(0), 0xFF607D8B);
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
  });
}

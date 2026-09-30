import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghin_golf/export.dart';
import 'package:ghin_golf/models.dart';
import 'package:ghin_golf/store.dart';

Course _course({String id = 'c1', String name = 'Cedar Hills'}) => Course(
  id: id,
  name: name,
  city: 'Austin',
  state: 'TX',
  tees: [],
  custom: true,
);

Round _round({String id = 'r1', String courseId = 'c1'}) => Round(
  id: id,
  courseId: courseId,
  teeId: 'tee-White',
  playedAt: DateTime.utc(2026, 9, 20, 15),
  courseHandicap: 7,
  handicapIndexAtPlay: 12.3,
  holes: [for (var i = 0; i < 18; i++) HoleScore(score: 4, putts: 2)],
);

void main() {
  group('parseBackup', () {
    test('reads back what toJson wrote', () {
      final rounds = [_round(), _round(id: 'r2')];
      final courses = [_course()];
      final b = parseBackup(toJson(rounds, courses, scoreColors: {0: 0xFF00FF00}));
      expect(b.rounds.length, 2);
      expect(b.courses.length, 1);
      expect(b.courses.first.name, 'Cedar Hills');
      expect(b.scoreColors?[0], 0xFF00FF00);
      expect(b.exportVersion, 1);
      expect(b.exportedAt, isNotNull);
    });

    test('round-trips a round faithfully', () {
      final original = _round();
      final b = parseBackup(toJson([original], [_course()]));
      final back = b.rounds.single;
      expect(back.id, original.id);
      expect(back.totalGross, original.totalGross);
      expect(back.courseHandicap, 7);
      expect(back.handicapIndexAtPlay, 12.3);
      expect(back.playedAt, original.playedAt);
    });

    test('an empty backup parses to an empty one', () {
      final b = parseBackup(toJson([], []));
      expect(b.rounds, isEmpty);
      expect(b.courses, isEmpty);
    });

    test('rejects text that is not JSON', () {
      expect(
        () => parseBackup('not json at all'),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('rejects JSON that is not an object', () {
      expect(
        () => parseBackup('[1,2,3]'),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('rejects unrelated JSON with no rounds', () {
      // Some other app's settings file must not import as an empty history.
      expect(
        () => parseBackup('{"theme":"dark","rounds":42}'),
        throwsA(isA<BackupFormatException>()),
      );
      expect(
        () => parseBackup('{"theme":"dark"}'),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('names the round that is unreadable', () {
      final text = jsonEncode({
        'rounds': [
          _round(id: 'ok').toJson(),
          {'id': 'broken'}, // no courseId, no holes
        ],
      });
      expect(
        () => parseBackup(text),
        throwsA(
          isA<BackupFormatException>().having(
            (e) => e.message,
            'message',
            contains('Round 2'),
          ),
        ),
      );
    });

    test('a bad course does not sink the rounds', () {
      // Losing a custom course is recoverable; losing the rounds is not, so
      // the courses are read leniently on purpose.
      final text = jsonEncode({
        'rounds': [_round().toJson()],
        'customCourses': [
          'garbage',
          {'id': 'c1', 'name': 'Good', 'tees': <Object>[]},
        ],
      });
      final b = parseBackup(text);
      expect(b.rounds.length, 1);
      expect(b.courses.map((c) => c.name), ['Good']);
    });

    test('a missing scoreColors key means leave colors alone', () {
      final b = parseBackup(jsonEncode({'rounds': []}));
      expect(b.scoreColors, isNull);
    });

    test('skips nonsense color entries instead of failing', () {
      final b = parseBackup(
        jsonEncode({
          'rounds': [],
          'scoreColors': {'x': 1, '0': 255, '1': 'nope'},
        }),
      );
      expect(b.scoreColors, {0: 255});
    });
  });

  group('GolfStore.importBackup', () {
    late GolfStore store;

    setUp(() {
      store = GolfStore();
      store.rounds = [];
      store.courses = [_course()];
    });

    test('adds the rounds in the backup', () async {
      final r = await store.importBackup(parseBackup(toJson([_round()], [_course()])));
      expect(r.added, 1);
      expect(store.rounds.length, 1);
      expect(store.rounds.single.id, 'r1');
    });

    test('keeps the rounds already there', () async {
      // The point of a restore: the current history must survive it.
      store.rounds = [_round(id: 'existing')];
      await store.importBackup(parseBackup(toJson([_round(id: 'new')], [_course()])));
      expect(store.rounds.map((r) => r.id).toSet(), {'existing', 'new'});
    });

    test('importing the same file twice adds nothing the second time', () async {
      final b = parseBackup(toJson([_round()], [_course()]));
      expect((await store.importBackup(b)).added, 1);
      final second = await store.importBackup(b);
      expect(second.added, 0);
      expect(second.skipped, 1);
      expect(store.rounds.length, 1);
    });

    test('reports duplicates as skipped rather than silently', () async {
      final b = parseBackup(toJson([_round(), _round(id: 'r2')], [_course()]));
      store.rounds = [_round()];
      final r = await store.importBackup(b);
      expect(r.added, 1);
      expect(r.skipped, 1);
    });

    test('brings custom courses across so rounds can resolve', () async {
      store.courses = [];
      final r = await store.importBackup(
        parseBackup(toJson([_round()], [_course(name: 'Backup Course')])),
      );
      expect(r.coursesAdded, 1);
      expect(store.courses.map((c) => c.name), contains('Backup Course'));
    });

    test('does not overwrite a course the app already has', () async {
      // Ids collide with the bundled courses, whose edited pars are what the
      // existing rounds were scored against.
      store.courses = [_course(name: 'My edited version')];
      final r = await store.importBackup(
        parseBackup(toJson([], [_course(name: 'Backup version')])),
      );
      expect(r.coursesAdded, 0);
      expect(store.courses.single.name, 'My edited version');
    });

    test('applies score colors from the backup', () async {
      final before = store.scoreColorValue(0);
      await store.importBackup(
        parseBackup(toJson([], [], scoreColors: {0: 0xFF123456})),
      );
      expect(store.scoreColorValue(0), 0xFF123456);
      expect(store.scoreColorValue(0), isNot(before));
    });

    test('leaves colors alone when the backup carries none', () async {
      store.setScoreColor(0, 0xFF999999);
      await store.importBackup(parseBackup(jsonEncode({'rounds': []})));
      expect(store.scoreColorValue(0), 0xFF999999);
    });

    test('a round survives the import with its scores intact', () async {
      await store.importBackup(parseBackup(toJson([_round()], [_course()])));
      final r = store.rounds.single;
      expect(r.holes.length, 18);
      expect(r.totalGross, 72);
      expect(r.totalPutts, 36);
    });
  });
}

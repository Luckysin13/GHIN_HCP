import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghin_golf/csv_import.dart';
import 'package:ghin_golf/export.dart';
import 'package:ghin_golf/models.dart';
import 'package:ghin_golf/store.dart';

/// Builds a row in the exporter's own format.
///
/// Every test here builds its input through this rather than by pasting a CSV
/// line, and the header comes from [csvHeader] itself. A hand-written test row
/// silently stops testing anything the moment a column is added to the export,
/// and the failure looks like a parser bug.
String row({
  String id = 'r1',
  String playedAt = '2026-03-04T09:30:00.000',
  String course = 'Shadow Creek',
  String tee = 'Blue',
  String scores = '4 4 3 5 4 4 5 6 5',
  int holes = 9,
  int startHole = 1,
  String par = '36',
  String gross = '78',
  String toPar = '+6',
  String handicap = '12',
  String index = '14.2',
  String rating = '72.4',
  String slope = '128',
  String diff = '6.8',
  String adj = '84.8',
  String putts = '',
  String penalties = '',
}) => [
  id,
  playedAt,
  course,
  tee,
  '$holes',
  '$startHole',
  par,
  gross,
  toPar,
  handicap,
  index,
  rating,
  slope,
  diff,
  adj,
  putts,
  penalties,
  scores,
].join(',');

/// A whole file: the real header, then [rows].
String file(List<String> rows) =>
    '${csvHeader.join(',')}\n${rows.join('\n')}\n';

void main() {
  group('CSV reader', () {
    test('reads a row back into the round the exporter wrote', () {
      final rows = parseCsv(file([row()]));
      expect(rows, hasLength(1));
      final r = rows.single;
      expect(r.id, 'r1');
      expect(r.playedAt, DateTime(2026, 3, 4, 9, 30));
      expect(r.courseName, 'Shadow Creek');
      expect(r.teeName, 'Blue');
      expect(r.scores, [4, 4, 3, 5, 4, 4, 5, 6, 5]);
      expect(r.startHole, 0);
      expect(r.parTotal, 36);
      expect(r.rating, 72.4);
      expect(r.slope, 128);
      expect(r.indexAtPlay, 14.2);
      expect(r.isTournament, isFalse);
    });

    test('a round the exporter wrote round-trips back to the same scores', () {
      final original = Round(
        id: 'x',
        courseId: 'c',
        teeId: 't',
        playedAt: DateTime(2026, 3, 4, 9, 30),
        holes: [
          for (var s in [4, 5, 3, 6, 4, 4, 5, 4, 7, 4, 4, 3, 5, 4, 6, 5, 4, 4])
            HoleScore(score: s),
        ],
        courseHandicap: 12,
        handicapIndexAtPlay: 14.2,
      );
      final text = toCsv(
        [original],
        courseById: (_) => null,
        teeById: (_, _) => null,
      );
      final back = parseCsv(text).single;
      expect(back.scores, [for (final h in original.holes) h.score]);
      expect(back.playedAt, original.playedAt);
      expect(back.startHole, original.startHole);
      expect(back.courseHandicap, 12);
    });

    test('a nine-hole row is a nine-hole round, not a short 18', () {
      final r = parseCsv(file([row()])).single;
      expect(r.toRound(courseId: 'c', teeId: 't').holes, hasLength(9));
    });

    test('honours start_hole for a back-nine round', () {
      final r = parseCsv(
        file([row(startHole: 10, par: '36', scores: '4 4 4 4 4 4 4 4 5')]),
      ).single;
      expect(r.startHole, 9);
      expect(r.toRound(courseId: 'c', teeId: 't').startHole, 9);
    });

    test('still reads the tournament column in older CSV files', () {
      final oldHeader = [...csvHeader]
        ..insert(csvHeader.indexOf('scores'), 'tournament');
      final oldRow = row().split(',')
        ..insert(csvHeader.indexOf('scores'), 'yes');
      expect(
        parseCsv(
          '${oldHeader.join(',')}\n${oldRow.join(',')}\n',
        ).single.isTournament,
        isTrue,
      );
    });

    test('a quoted field keeps its commas, quotes and newline', () {
      final rows = parseCsv(
        file([
          row(course: '"Pine, Valley"'),
          row(id: 'r2', course: '"He said ""go"""'),
        ]),
      );
      expect(rows[0].courseName, 'Pine, Valley');
      expect(rows[1].courseName, 'He said "go"');
    });

    test('a field of only escaped quotes is read as one quote', () {
      // The case that separates "consume the pair" from "look at the pair
      // and carry on": four quotes are an opening quote, one escaped quote,
      // and a closing quote. Read one quote at a time it comes out as two.
      final rows = parseCsv(file([row(course: '""""')]));
      expect(rows.single.courseName, '"');
    });

    test('a quoted field that is only a comma is not two empty cells', () {
      final rows = parseCsv(file([row(course: '","')]));
      expect(rows.single.courseName, ',');
    });

    test('a newline inside a quoted field does not end the row', () {
      final rows = parseCsv(
        file([row(course: '"Two\nLines"'), row(id: 'r2', course: 'Second')]),
      );
      expect(rows, hasLength(2));
      expect(rows[0].courseName, 'Two\nLines');
      expect(rows[1].courseName, 'Second');
    });

    test('strips the BOM Excel puts on a UTF-8 file', () {
      final rows = parseCsv('﻿${file([row()])}');
      expect(rows, hasLength(1));
      expect(rows.single.courseName, 'Shadow Creek');
    });

    test('tolerates CRLF line endings', () {
      final rows = parseCsv(file([row()]).replaceAll('\n', '\r\n'));
      expect(rows, hasLength(1));
      expect(rows.single.courseName, 'Shadow Creek');
    });

    test('a row whose scores are not scores is dropped, not guessed at', () {
      expect(
        () => parseCsv(file([row(scores: 'not a score')])),
        throwsA(isA<CsvFormatException>()),
      );
    });

    test('a score outside 1..12 is not a score', () {
      expect(
        () => parseCsv(file([row(scores: '4 4 3 5 4 4 5 6 99')])),
        throwsA(isA<CsvFormatException>()),
      );
    });

    test('a file without the columns a round needs is refused by name', () {
      expect(
        () => parseCsv('a,b,c\n1,2,3\n'),
        throwsA(
          isA<CsvFormatException>().having(
            (e) => e.message,
            'message',
            contains('played_at'),
          ),
        ),
      );
    });

    test('an empty file says so rather than importing nothing quietly', () {
      expect(() => parseCsv(''), throwsA(isA<CsvFormatException>()));
    });

    test('the unresolved "?" name the exporter writes is not a course', () {
      final r = parseCsv(
        file([row(course: '?', tee: '?', rating: '', slope: '')]),
      ).single;
      expect(r.courseName, isEmpty);
      expect(r.teeName, isEmpty);
    });

    test('a row with a blank id is not given an empty id', () {
      final r = parseCsv(file([row(id: '')])).single;
      expect(r.id, isNull);
      expect(r.toRound(courseId: 'c', teeId: 't').id, isNotEmpty);
    });

    test(
      'a missing handicap index stays unknown when converted to a round',
      () {
        final r = parseCsv(
          file([row(id: '', index: '')]),
        ).single.toRound(courseId: 'c', teeId: 't');
        expect(r.handicapIndexAtPlay, isNull);
      },
    );

    test('id-less rounds on opposite nines receive distinct ids', () {
      final rows = parseCsv(
        file([row(id: '', startHole: 1), row(id: '', startHole: 10)]),
      );
      expect(
        rows[0].toRound(courseId: 'c', teeId: 't').id,
        isNot(rows[1].toRound(courseId: 'c', teeId: 't').id),
      );
    });

    test('two id-less rows that differ produce two distinct rounds', () {
      final rows = parseCsv(
        file([row(id: '', course: 'A'), row(id: '', course: 'B')]),
      );
      expect(
        rows[0].toRound(courseId: 'c', teeId: 't').id,
        isNot(rows[1].toRound(courseId: 'c', teeId: 't').id),
      );
    });

    test('a slash date is read month-first, the locale the app ships in', () {
      // 04/03/2026 is genuinely ambiguous. Month-first is what the locale
      // that produced these files means by it, and the exporter writes ISO so
      // this fallback only ever runs on a hand-edited file.
      final r = parseCsv(file([row(playedAt: '04/03/2026')])).single;
      expect(r.playedAt, DateTime(2026, 4, 3));
    });

    test('a two-digit year is expanded rather than read as year 26', () {
      expect(
        parseCsv(file([row(playedAt: '04/03/26')])).single.playedAt,
        DateTime(2026, 4, 3),
      );
    });

    test('a day above 12 is read as the day, not the month', () {
      final r = parseCsv(file([row(playedAt: '25/03/2026')])).single;
      expect(r.playedAt, DateTime(2026, 3, 25));
    });

    test('a row with no usable date is dropped, not filed under the epoch', () {
      expect(
        () => parseCsv(file([row(playedAt: 'sometime last week')])),
        throwsA(isA<CsvFormatException>()),
      );
    });
  });

  group('CSV import into the store', () {
    late Directory dir;
    late GolfStore store;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('ghin-csv-import');
      GolfStore.testFilePath = '${dir.path}/save.json';
      store = GolfStore();
      await store.load();
      // load() seeds the bundled courses, and these tests are about what an
      // import does to a store that does not already have the course.
      store.courses = [];
    });

    tearDown(() async {
      GolfStore.testFilePath = null;
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    Course seedCourse({String name = 'Shadow Creek'}) => Course(
      id: 'c1',
      name: name,
      city: '',
      state: '',
      tees: [
        Tee(
          id: 't1',
          name: 'Blue',
          rating: 71.8,
          slope: 124,
          holes: [
            for (var i = 1; i <= 9; i++)
              HoleInfo(number: i, par: 4, yardage: 0, strokeIndex: i),
          ],
        ),
      ],
    );

    List<CsvRound> twoRounds() => parseCsv(
      file([row(), row(id: 'r2', playedAt: '2026-03-11T09:30:00.000')]),
    );

    test('matches an existing course by name, ignoring case and spacing', () {
      store.courses.add(seedCourse(name: 'shadow   creek'));
      final r = store.importCsv(twoRounds());
      expect(r.added, 2);
      expect(r.coursesAdded, 0);
      expect(store.courses, hasLength(1));
      expect(store.rounds.first.courseId, 'c1');
    });

    test('posts against the tee it names', () {
      store.courses.add(seedCourse());
      store.importCsv(twoRounds());
      expect(store.rounds.first.teeId, 't1');
    });

    test('a course the app lacks is built, and counted as built', () {
      final r = store.importCsv(twoRounds());
      expect(r.coursesAdded, 1);
      expect(r.added, 2);
      expect(store.courses.single.name, 'Shadow Creek');
      expect(store.courses.single.custom, isTrue);
    });

    test('two rounds at one unknown course build one course, not two', () {
      final r = store.importCsv(twoRounds());
      expect(r.coursesAdded, 1);
      expect(store.courses, hasLength(1));
      expect(store.rounds, hasLength(2));
      expect(store.rounds.map((x) => x.courseId).toSet(), hasLength(1));
    });

    test(
      'a back-nine round reconstructs an 18-hole tee at the right holes',
      () {
        store.importCsv(
          parseCsv(
            file([
              row(
                id: '',
                startHole: 10,
                par: '45',
                scores: '4 4 4 4 4 4 4 4 4',
              ),
            ]),
          ),
        );
        final tee = store.courses.single.tees.single;
        expect(tee.holes, hasLength(18));
        expect(tee.parTotalFrom(9, 9), 45);
        expect(store.rounds.single.parPlayed(tee), 45);
      },
    );

    test('a rebuilt course spreads the row par total over its holes', () {
      // Par 34 over 9 holes on purpose: 36/9 is 4, which is indistinguishable
      // from a hardcoded par 4 and would let that bug pass. This one needs a
      // 3 in it, so a flat 4 in every hole fails.
      store.importCsv(parseCsv(file([row(par: '34')])));
      final tee = store.courses.single.tees.single;
      expect(tee.holes, hasLength(9));
      expect(tee.holes.fold<int>(0, (s, h) => s + h.par), 34);
      expect(tee.holes.map((h) => h.par), contains(3));
    });

    test('a par total that divides evenly gives every hole the same par', () {
      store.importCsv(parseCsv(file([row(par: '36')])));
      expect(
        store.courses.single.tees.single.holes.map((h) => h.par),
        everyElement(4),
      );
    });

    test('an 18-hole row builds an 18-hole course', () {
      store.importCsv(
        parseCsv(
          file([
            row(
              holes: 18,
              par: '71',
              scores: '4 4 4 4 4 4 4 4 4 4 4 4 4 4 4 4 4 5',
            ),
          ]),
        ),
      );
      final tee = store.courses.single.tees.single;
      expect(tee.holes, hasLength(18));
      expect(tee.holes.fold<int>(0, (s, h) => s + h.par), 71);
      expect(tee.holes.last.number, 18);
    });

    test('a rebuilt course with no par column falls back to par 4', () {
      store.importCsv(parseCsv(file([row(course: 'Nowhere', par: '')])));
      expect(
        store.courses.single.tees.single.holes.every((h) => h.par == 4),
        isTrue,
      );
    });

    test('a rebuilt course keeps the rating and slope the file carried', () {
      store.importCsv(twoRounds());
      final tee = store.courses.single.tees.single;
      expect(tee.rating, 72.4);
      expect(tee.slope, 128);
    });

    test('a tee the course lacks is added rather than substituted', () {
      store.courses.add(seedCourse());
      final r = store.importCsv(parseCsv(file([row(tee: 'Gold')])));
      expect(r.coursesAdded, 0);
      expect(store.courses.single.tees.map((t) => t.name), ['Blue', 'Gold']);
      expect(store.rounds.first.teeId, isNot('t1'));
    });

    test('importing the same file twice adds nothing the second time', () {
      store.importCsv(twoRounds());
      final again = store.importCsv(twoRounds());
      expect(again.added, 0);
      expect(again.skipped, 2);
      expect(store.rounds, hasLength(2));
    });

    test('a row repeated inside one file is posted once', () {
      final r = store.importCsv(parseCsv(file([row(), row(id: 'r9')])));
      expect(r.added, 1);
      expect(r.skipped, 1);
    });

    test('a round with a different score is a different round', () {
      store.importCsv(twoRounds());
      expect(
        store
            .importCsv(parseCsv(file([row(scores: '5 4 3 5 4 4 5 6 5')])))
            .added,
        1,
      );
      expect(store.rounds, hasLength(3));
    });

    test('a round with a different id but the same scores is not doubled', () {
      store.importCsv(twoRounds());
      expect(store.importCsv(parseCsv(file([row(id: 'zzz')]))).added, 0);
      expect(store.rounds, hasLength(2));
    });

    test(
      'duplicate detection ignores course and tee name case and spacing',
      () {
        store.importCsv(twoRounds());
        final reformatted = parseCsv(
          file([
            row(id: 'different-id', course: '  shadow   creek ', tee: ' blue '),
          ]),
        );
        final result = store.importCsv(reformatted);
        expect(result.added, 0);
        expect(result.skipped, 1);
        expect(store.rounds, hasLength(2));
      },
    );

    test('same scores on opposite nines are distinct rounds', () {
      final front = parseCsv(file([row(id: 'front', startHole: 1)]));
      final back = parseCsv(file([row(id: 'back', startHole: 10)]));
      store.importCsv(front);
      final result = store.importCsv(back);
      expect(result.added, 1);
      expect(store.rounds, hasLength(2));
    });

    test('preview counts exactly what the import adds', () {
      final rows = twoRounds();
      expect(store.previewCsv(rows).roundsAdded, 2);
      store.importCsv(rows);
      final p = store.previewCsv(rows);
      expect(p.roundsAdded, 0);
      expect(p.roundsSkipped, 2);
    });

    test('preview counts a course that would have to be built', () {
      expect(store.previewCsv(twoRounds()).coursesAdded, 1);
    });

    test('preview does not touch the store', () {
      store.previewCsv(twoRounds());
      expect(store.courses, isEmpty);
      expect(store.rounds, isEmpty);
    });

    test('the import survives a reload', () async {
      store.importCsv(twoRounds());
      // The store saves without being awaited, as every other write does, so
      // the reload has to wait for the write rather than race it.
      await store.save();
      final reloaded = GolfStore();
      await reloaded.load();
      expect(reloaded.rounds, hasLength(2));
    });

    test('the import hands back the ids it added, so it can be undone', () {
      final r = store.importCsv(twoRounds());
      expect(r.roundIds, hasLength(2));
      for (final id in r.roundIds) {
        expect(store.rounds.map((x) => x.id), contains(id));
      }
    });

    test('undoing an import empties it, and takes nothing else', () {
      final r = store.importCsv(twoRounds());
      expect(store.removeRounds(r.roundIds), 2);
      expect(store.rounds, isEmpty);
    });

    test('undoing leaves a round posted after the import alone', () {
      final r = store.importCsv(twoRounds());
      store.addRound(
        Round(
          id: 'later',
          courseId: 'c1',
          teeId: 't1',
          playedAt: DateTime(2026, 4),
          holes: [HoleScore(score: 4)],
        ),
      );
      expect(store.removeRounds(r.roundIds), 2);
      expect(store.rounds.map((x) => x.id), ['later']);
    });

    test('undoing keeps the surviving history in its original order', () {
      store.addRound(
        Round(
          id: 'older',
          courseId: 'c1',
          teeId: 't1',
          playedAt: DateTime(2026, 1),
          holes: [HoleScore(score: 4)],
        ),
      );
      final r = store.importCsv(twoRounds());
      store.removeRounds(r.roundIds);
      expect(store.rounds.map((x) => x.id), ['older']);
    });

    test('undoing an import that was already undone removes nothing', () {
      final r = store.importCsv(twoRounds());
      store.removeRounds(r.roundIds);
      expect(store.removeRounds(r.roundIds), 0);
    });
  });
}

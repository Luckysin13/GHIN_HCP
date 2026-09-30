import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghin_golf/export.dart';
import 'package:ghin_golf/models.dart';

Tee _tee({
  String name = 'White',
  double rating = 70.0,
  int slope = 120,
  int par = 4,
  List<int>? pars,
}) => Tee(
  id: 'tee-$name',
  name: name,
  rating: rating,
  slope: slope,
  holes: [
    for (var i = 0; i < 18; i++)
      HoleInfo(
        number: i + 1,
        par: pars?[i] ?? par,
        yardage: 400,
        strokeIndex: i + 1,
      ),
  ],
);

Course _course({
  String name = 'Cedar Hills',
  String id = 'c1',
  bool custom = false,
}) => Course(
  id: id,
  name: name,
  city: 'Austin',
  state: 'TX',
  tees: [],
  custom: custom,
);

Round _round({
  String id = 'r1',
  String courseId = 'c1',
  String teeId = 'tee-White',
  DateTime? playedAt,
  List<int>? scores,
  int startHole = 0,
  int courseHandicap = 0,
  bool isTournament = false,
}) {
  final s = scores ?? List<int>.filled(18, 4);
  return Round(
    id: id,
    courseId: courseId,
    teeId: teeId,
    playedAt: playedAt ?? DateTime.utc(2026, 9, 20, 15),
    isTournament: isTournament,
    courseHandicap: courseHandicap,
    handicapIndexAtPlay: 12.3,
    startHole: startHole,
    holes: [
      for (var i = 0; i < s.length; i++)
        HoleScore(score: s[i], putts: 2, penalties: 0),
    ],
  );
}

/// Splits CSV into rows of fields, honouring quoted fields.
List<List<String>> _rows(String csv) {
  final out = <List<String>>[];
  var field = StringBuffer();
  var row = <String>[];
  var inQuotes = false;
  for (var i = 0; i < csv.length; i++) {
    final c = csv[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < csv.length && csv[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(c);
      }
      continue;
    }
    if (c == '"') {
      inQuotes = true;
    } else if (c == ',') {
      row.add(field.toString());
      field = StringBuffer();
    } else if (c == '\n') {
      row.add(field.toString());
      out.add(row);
      row = <String>[];
      field = StringBuffer();
    } else if (c != '\r') {
      field.write(c);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    out.add(row);
  }
  return out;
}

void main() {
  final tee = _tee();
  final course = _course();
  Course? byId(String id) => id == 'c1' ? course : null;
  Tee? teeOf(String cid, String tid) => cid == 'c1' ? tee : null;

  group('toCsv', () {
    test('writes a header and one row per round', () {
      final csv = toCsv(
        [_round(), _round(id: 'r2')],
        courseById: byId,
        teeById: teeOf,
      );
      final rows = _rows(csv);
      expect(rows.length, 3);
      expect(rows.first, csvHeader);
      expect(rows[1][csvHeader.indexOf('id')], 'r1');
      expect(rows[2][csvHeader.indexOf('id')], 'r2');
    });

    test('sorts oldest first regardless of input order', () {
      final csv = toCsv(
        [
          _round(id: 'new', playedAt: DateTime.utc(2026, 9, 27)),
          _round(id: 'old', playedAt: DateTime.utc(2026, 6, 1)),
        ],
        courseById: byId,
        teeById: teeOf,
      );
      final ids = _rows(csv).skip(1).map((r) => r.first).toList();
      expect(ids, ['old', 'new']);
    });

    test('resolves course and tee names, not ids', () {
      final csv = toCsv([_round()], courseById: byId, teeById: teeOf);
      final row = _rows(csv)[1];
      expect(row[csvHeader.indexOf('course')], 'Cedar Hills');
      expect(row[csvHeader.indexOf('tee')], 'White');
    });

    test('computes par, gross and to-par from the tee', () {
      final csv = toCsv(
        [_round(scores: List<int>.filled(18, 5))],
        courseById: byId,
        teeById: teeOf,
      );
      final row = _rows(csv)[1];
      expect(row[csvHeader.indexOf('par')], '72');
      expect(row[csvHeader.indexOf('gross')], '90');
      expect(row[csvHeader.indexOf('to_par')], '+18');
    });

    test('to_par is signed, so an under-par round reads as negative', () {
      final csv = toCsv(
        [_round(scores: List<int>.filled(18, 3))],
        courseById: byId,
        teeById: teeOf,
      );
      expect(_rows(csv)[1][csvHeader.indexOf('to_par')], '-18');
    });

    test('par varies by hole, not a flat 4', () {
      final pars = List<int>.filled(18, 4);
      pars[0] = 3;
      pars[17] = 5;
      final csv = toCsv(
        [_round()],
        courseById: byId,
        teeById: (c, t) => _tee(pars: pars),
      );
      // 16*4 + 3 + 5 = 72
      expect(_rows(csv)[1][csvHeader.indexOf('par')], '72');
    });

    test('a nine-hole round reports its own par and start hole', () {
      final csv = toCsv(
        [_round(startHole: 9, scores: List<int>.filled(9, 4))],
        courseById: byId,
        teeById: teeOf,
      );
      final row = _rows(csv)[1];
      expect(row[csvHeader.indexOf('holes')], '9');
      expect(row[csvHeader.indexOf('start_hole')], '10');
      expect(row[csvHeader.indexOf('par')], '36');
    });

    test('quotes a course name containing a comma', () {
      final csv = toCsv(
        [_round()],
        courseById: (_) => _course(name: 'Cedar, Lakes'),
        teeById: teeOf,
      );
      expect(csv, contains('"Cedar, Lakes"'));
      // The field must survive a round trip as one value, not two.
      expect(_rows(csv)[1][csvHeader.indexOf('course')], 'Cedar, Lakes');
    });

    test('escapes a double quote by doubling it', () {
      final csv = toCsv(
        [_round()],
        courseById: (_) => _course(name: 'The "Big" Nine'),
        teeById: teeOf,
      );
      expect(csv, contains('"The ""Big"" Nine"'));
      expect(_rows(csv)[1][csvHeader.indexOf('course')], 'The "Big" Nine');
    });

    test('keeps a round whose course is gone, marked with a placeholder', () {
      // A backup that quietly drops an unresolvable round would be worse than
      // one with a visible hole in it.
      final csv = toCsv(
        [_round(courseId: 'gone')],
        courseById: byId,
        teeById: teeOf,
      );
      final row = _rows(csv)[1];
      expect(row[csvHeader.indexOf('id')], 'r1');
      expect(row[csvHeader.indexOf('course')], '?');
      expect(row[csvHeader.indexOf('tee')], '?');
      expect(row[csvHeader.indexOf('par')], '');
      expect(row[csvHeader.indexOf('to_par')], '');
    });

    test('leaves a differential blank rather than guessing', () {
      // Differential is only defined for an 18-hole round on an 18-hole tee.
      final csv = toCsv(
        [_round(startHole: 9, scores: List<int>.filled(9, 4))],
        courseById: byId,
        teeById: teeOf,
        differentialFor: (r, t) => r.differential(t),
      );
      expect(_rows(csv)[1][csvHeader.indexOf('differential')], '');
    });

    test('fills the differential when one can be computed', () {
      final csv = toCsv(
        [_round()],
        courseById: byId,
        teeById: teeOf,
        differentialFor: (r, t) => r.differential(t),
      );
      expect(
        RegExp(
          r'^\d+\.\d\d$',
        ).hasMatch(_rows(csv)[1][csvHeader.indexOf('differential')]),
        isTrue,
      );
    });

    test('formats two decimals so columns line up', () {
      final csv = toCsv([_round()], courseById: byId, teeById: teeOf);
      expect(_rows(csv)[1][csvHeader.indexOf('index_at_play')], '12.30');
    });

    test('keeps every score in one cell', () {
      final csv = toCsv(
        [
          _round(scores: [4, 3, 5, ...List<int>.filled(15, 4)]),
        ],
        courseById: byId,
        teeById: teeOf,
      );
      expect(
        _rows(csv)[1][csvHeader.indexOf('scores')],
        '4 3 5 ${List.filled(15, '4').join(' ')}',
      );
    });

    test('does not export the removed tournament field', () {
      final csv = toCsv(
        [_round(isTournament: true)],
        courseById: byId,
        teeById: teeOf,
      );
      final rows = _rows(csv);
      expect(csvHeader, isNot(contains('tournament')));
      expect(rows.first, isNot(contains('tournament')));
      expect(rows[1], hasLength(csvHeader.length));
    });

    test('an empty history is a header and nothing else', () {
      final csv = toCsv([], courseById: byId, teeById: teeOf);
      expect(_rows(csv).length, 1);
    });

    test('no round is lost for any reason', () {
      final rounds = [
        _round(id: 'a'),
        _round(id: 'b', courseId: 'missing'),
        _round(id: 'c', startHole: 9, scores: List<int>.filled(9, 5)),
        _round(id: 'd', isTournament: true),
      ];
      final ids = _rows(
        toCsv(rounds, courseById: byId, teeById: teeOf),
      ).skip(1).map((r) => r.first).toSet();
      expect(ids, {'a', 'b', 'c', 'd'});
    });
  });

  group('toJson', () {
    test('is valid JSON with a version and timestamp', () {
      final j = jsonDecode(toJson([_round()], [course]));
      expect(j['exportVersion'], 1);
      expect(j['exportedAt'], isA<String>());
      expect(DateTime.parse(j['exportedAt']).toUtc(), isA<DateTime>());
    });

    test('round-trips back into a Round', () {
      final original = _round(isTournament: true, courseHandicap: 7);
      final j = jsonDecode(toJson([original], [course]));
      final back = Round.fromJson(
        Map<String, dynamic>.from((j['rounds'] as List).first as Map),
      );
      expect(back.id, original.id);
      expect(back.holes.length, 18);
      expect(back.totalGross, original.totalGross);
      expect(back.isTournament, isTrue);
      expect(back.courseHandicap, 7);
      expect(back.playedAt, original.playedAt);
    });

    test('carries every course, custom and bundled', () {
      // A round whose course is missing has no differential, so the backup
      // has to bring the course with it. The bundled courses come too, so the
      // file is a real snapshot rather than a partial one.
      final custom = _course(id: 'c9', name: 'My Home Course', custom: true);
      final j = jsonDecode(toJson([], [course, custom]));
      final names = (j['courses'] as List)
          .map((e) => Course.fromJson(Map<String, dynamic>.from(e as Map)).name)
          .toList();
      expect(names, containsAll(['Cedar Hills', 'My Home Course']));
    });

    test('includes the course photos inline', () {
      // They live in app-private storage and courses only hold a path, so
      // without the bytes a restored course keeps a dangling reference.
      final j = jsonDecode(
        toJson([], [course], photos: {'c1.jpg': 'aGVsbG8='}),
      );
      expect((j['photos'] as Map)['c1.jpg'], 'aGVsbG8=');
    });

    test('stamps the app version', () {
      final j = jsonDecode(toJson([], [], appVersion: '1.0.0+1'));
      expect(j['appVersion'], '1.0.0+1');
    });

    test('includes score colors so a restore looks the same', () {
      final j = jsonDecode(
        toJson(
          [_round()],
          [course],
          scoreColors: {0: 0xFF123456, 1: 0xFF654321},
        ),
      );
      expect((j['scoreColors'] as Map)['0'], 0xFF123456);
      expect((j['scoreColors'] as Map)['1'], 0xFF654321);
    });

    test('an empty history still exports a valid file', () {
      expect(jsonDecode(toJson([], [])), isA<Map<String, dynamic>>());
    });
  });
}

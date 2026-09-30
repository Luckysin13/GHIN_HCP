import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghin_golf/models.dart';
import 'package:ghin_golf/store.dart';

/// Exercises the store's own export entry points against a real store, since
/// those are what the UI calls. The format builders are tested directly in
/// export_test.dart; this checks the lookups bind to the store's data.
void main() {
  late GolfStore store;

  setUp(() {
    store = GolfStore();
    store.rounds = [];
  });

  Tee tee(String name) => Tee(
    id: 'tee-$name',
    name: name,
    rating: 71.2,
    slope: 124,
    holes: [
      for (var i = 0; i < 18; i++)
        HoleInfo(number: i + 1, par: 4, yardage: 410, strokeIndex: i + 1),
    ],
  );

  void post({
    String id = 'r1',
    String courseId = 'c1',
    String teeId = 'tee-White',
    int handicap = 9,
  }) {
    store.rounds = [
      ...store.rounds,
      Round(
        id: id,
        courseId: courseId,
        teeId: teeId,
        playedAt: DateTime.utc(2026, 9, 1),
        courseHandicap: handicap,
        handicapIndexAtPlay: 14.2,
        holes: [
          for (var i = 0; i < 18; i++)
            HoleScore(score: 4, putts: 2, penalties: 0),
        ],
      ),
    ];
  }

  test('CSV resolves the course and tee the store holds', () {
    store.courses = [
      Course(
        id: 'c1',
        name: 'Bent Creek',
        city: 'Austin',
        state: 'TX',
        tees: [tee('White')],
      ),
    ];
    post();
    final rows = store.exportRoundsCsv().split('\n');
    expect(rows.length, 3); // header + round + trailing newline
    expect(rows[1], contains('Bent Creek'));
    expect(rows[1], contains('White'));
    expect(rows[1], contains('71.2'));
  });

  test('CSV fills a real differential through the store', () {
    store.courses = [
      Course(
        id: 'c1',
        name: 'Bent Creek',
        city: '',
        state: '',
        tees: [tee('White')],
      ),
    ];
    post();
    final csv = store.exportRoundsCsv();
    // Column 14 is differential; it must be a real figure, not blank.
    final cells = csv.split('\n')[1].split(',');
    expect(RegExp(r'^\d+\.\d\d$').hasMatch(cells[13]), isTrue);
  });

  test('CSV reports putts and penalties from the round', () {
    store.courses = [
      Course(
        id: 'c1',
        name: 'Bent Creek',
        city: '',
        state: '',
        tees: [tee('White')],
      ),
    ];
    post();
    final cells = store.exportRoundsCsv().split('\n')[1].split(',');
    expect(cells[15], '36'); // 18 holes * 2 putts
    expect(cells[16], '0');
  });

  test('a round with no matching tee is kept, not dropped', () {
    store.courses = [
      Course(id: 'c1', name: 'Bent Creek', city: '', state: '', tees: []),
    ];
    post();
    final csv = store.exportRoundsCsv();
    expect(csv.split('\n').where((l) => l.trim().isNotEmpty).length, 2);
    expect(csv, contains('?'));
  });

  test('empty history exports a header-only CSV', () {
    expect(store.exportRoundsCsv().trim().split('\n').length, 1);
  });

  test('JSON carries the store scores, not a default map', () {
    store.setScoreColor(0, 0xFFABCDEF);
    final j = jsonDecode(store.exportRoundsJson()) as Map<String, dynamic>;
    final colors = j['scoreColors'] as Map<String, dynamic>;
    // The store's value, not the default for par, which would be a
    // different ARGB entirely.
    expect(colors['0'], 0xFFABCDEF);
    expect(colors['0'], isNot(defaultScoreColors[0]));
  });

  test('JSON includes custom courses from the store', () {
    store.courses = [
      Course(
        id: 'cx',
        name: 'My Course',
        city: '',
        state: '',
        tees: [],
        custom: true,
      ),
    ];
    expect(store.exportRoundsJson(), contains('My Course'));
  });
}

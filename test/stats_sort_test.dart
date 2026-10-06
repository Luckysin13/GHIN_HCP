import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ghin_golf/main.dart';
import 'package:ghin_golf/models.dart';
import 'package:ghin_golf/store.dart';

/// A Course sorts first alphabetically but was played long ago with bad
/// scores; Z Course was played recently and well. The three sort modes each
/// produce a different, unambiguous order.
GolfStore _seedStore() {
  Tee tee(String id) => Tee(
    id: id,
    name: 'White',
    rating: 72,
    slope: 113,
    holes: [
      for (var i = 0; i < 18; i++)
        HoleInfo(number: i + 1, par: 4, yardage: 400, strokeIndex: i + 1),
    ],
  );
  final store = GolfStore();
  store.courses = [
    Course(
      id: 'a',
      name: 'A Course',
      city: '',
      state: '',
      tees: [tee('a-white')],
      custom: true,
    ),
    Course(
      id: 'z',
      name: 'Z Course',
      city: '',
      state: '',
      tees: [tee('z-white')],
      custom: true,
    ),
  ];
  Round round(String id, String courseId, DateTime at, int perHole) => Round(
    id: id,
    courseId: courseId,
    teeId: '$courseId-white',
    playedAt: at,
    holes: [for (var i = 0; i < 18; i++) HoleScore(score: perHole, putts: 2)],
  );
  store.rounds = [
    round('a1', 'a', DateTime(2026, 1, 10), 6), // 108
    round('a2', 'a', DateTime(2026, 1, 12), 5), // 90
    round('z1', 'z', DateTime(2026, 9, 20), 4), // 72
  ];
  return store;
}

Future<void> _pumpStats(WidgetTester tester, GolfStore store) async {
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: StatsPage(store: store)));
  await tester.pumpAndSettle();
}

Future<void> _chooseSort(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const ValueKey('stats-sort')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('stats headers and default course sort', (tester) async {
    await _pumpStats(tester, _seedStore());

    expect(find.text('Courses Played'), findsOneWidget);
    expect(find.text('By course'), findsNothing);
    expect(find.text('ROUND BY ROUND'), findsNothing);
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(const ValueKey('stats-sort')),
          )
          .initialValue,
      'course',
    );
    // Alphabetical: A Course above Z Course.
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('stats-course-a'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('stats-course-z'))).dy,
      ),
    );
  });

  testWidgets('sorting stats by date puts the latest-played course first', (
    tester,
  ) async {
    await _pumpStats(tester, _seedStore());

    await _chooseSort(tester, 'Date');

    expect(
      tester.getTopLeft(find.byKey(const ValueKey('stats-course-z'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('stats-course-a'))).dy,
      ),
    );
  });

  testWidgets('round titles carry the front and back nine totals', (
    tester,
  ) async {
    final store = _seedStore();
    store.rounds = [
      Round(
        id: 'split',
        courseId: 'z',
        teeId: 'z-white',
        playedAt: DateTime(2026, 3, 1),
        holes: [
          for (var i = 0; i < 18; i++)
            HoleScore(score: i < 9 ? 4 : 5), // 36 front, 45 back, 81 total
        ],
      ),
      Round(
        id: 'back-only',
        courseId: 'z',
        teeId: 'z-white',
        playedAt: DateTime(2026, 3, 2),
        startHole: 9,
        holes: [for (var i = 0; i < 9; i++) HoleScore(score: 5)], // 45 back
      ),
    ];
    await _pumpStats(tester, store);

    await tester.tap(find.byKey(const ValueKey('stats-course-z')));
    await tester.pumpAndSettle();

    expect(
      find.text('Total: 81 • (F) 36 • (B) 45'),
      findsOneWidget,
    );
    // A back-nine-only round reports no front. The dash is safe from the
    // Date rows, which carry the em dash for other empty values.
    expect(
      find.text('Total: 45 • (F) — • (B) 45'),
      findsOneWidget,
    );
  });

  testWidgets('sorting stats by score orders rows best-first', (tester) async {
    await _pumpStats(tester, _seedStore());

    await _chooseSort(tester, 'Score');
    // Best course first, and best round first inside A Course.
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('stats-course-z'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('stats-course-a'))).dy,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('stats-course-a')));
    await tester.pumpAndSettle();
    expect(
      tester.getCenter(find.text('Total: 90 • (F) 45 • (B) 45')).dy,
      lessThan(tester.getCenter(find.text('Total: 108 • (F) 54 • (B) 54')).dy),
    );
  });

  testWidgets('sorting by date separates rounds into year blocks', (
    tester,
  ) async {
    final store = _seedStore();
    // A Course adds a 2025 round so its date-sorted list crosses years.
    store.rounds = [
      ...store.rounds,
      Round(
        id: 'a3',
        courseId: 'a',
        teeId: 'a-white',
        playedAt: DateTime(2025, 11, 2),
        holes: [for (var i = 0; i < 18; i++) HoleScore(score: 7, putts: 2)],
      ), // 126
    ];
    await _pumpStats(tester, store);

    await _chooseSort(tester, 'Date');
    await tester.tap(find.byKey(const ValueKey('stats-course-a')));
    await tester.pumpAndSettle();

    // A "2025" separator sits between the 2026 rounds and the 2025 round.
    final separator = find.text('2025');
    expect(separator, findsOneWidget);
    final sepDy = tester.getCenter(separator).dy;
    expect(
      sepDy,
      greaterThan(tester.getCenter(find.text('Total: 108 • (F) 54 • (B) 54')).dy),
    );
    expect(sepDy, lessThan(tester.getCenter(find.text('Total: 126 • (F) 63 • (B) 63')).dy));
  });

  testWidgets('year separators only appear under the Date sort', (
    tester,
  ) async {
    final store = _seedStore();
    store.rounds = [
      ...store.rounds,
      Round(
        id: 'a3',
        courseId: 'a',
        teeId: 'a-white',
        playedAt: DateTime(2025, 11, 2),
        holes: [for (var i = 0; i < 18; i++) HoleScore(score: 7, putts: 2)],
      ),
    ];
    await _pumpStats(tester, store);

    await tester.tap(find.byKey(const ValueKey('stats-course-a')));
    await tester.pumpAndSettle();
    expect(find.text('2025'), findsNothing);

    await _chooseSort(tester, 'Score');
    await tester.tap(find.byKey(const ValueKey('stats-course-a')));
    await tester.pumpAndSettle();
    expect(find.text('2025'), findsNothing);
  });
}

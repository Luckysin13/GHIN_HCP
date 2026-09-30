import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghin_golf/main.dart';
import 'package:ghin_golf/models.dart';
import 'package:ghin_golf/store.dart';

Round _round(String id, int par) => Round(
  id: id,
  courseId: 'c1',
  teeId: 'tee-White',
  // Local, not UTC: the row renders dates in local time, so a UTC midnight
  // would show as the previous day anywhere west of Greenwich.
  playedAt: DateTime(2026, 9, 20).add(Duration(days: par)),
  holes: [for (var i = 0; i < 18; i++) HoleScore(score: 4, putts: 2)],
);

GolfStore _store(List<Round> rounds) {
  final store = GolfStore()
    ..rounds = rounds
    ..courses = [
      Course(
        id: 'c1',
        name: 'Bent Creek',
        city: '',
        state: '',
        tees: [
          Tee(
            id: 'tee-White',
            name: 'White',
            rating: 71.2,
            slope: 124,
            holes: [
              for (var i = 0; i < 18; i++)
                HoleInfo(
                  number: i + 1,
                  par: 4,
                  yardage: 410,
                  strokeIndex: i + 1,
                ),
            ],
          ),
        ],
      ),
    ];
  return store;
}

void main() {
  /// The recent-rounds list sits below a tall quick-post card, so it has to
  /// be scrolled into view before it exists in the tree.
  Future<void> scrollToRounds(WidgetTester tester) async {
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
  }

  testWidgets('swiping a recent round deletes it', (tester) async {
    final store = _store([_round('r1', 0), _round('r2', 1)]);
    await tester.pumpWidget(MaterialApp(home: HomePage(store: store)));
    await tester.pumpAndSettle();

    await scrollToRounds(tester);
    expect(find.text('RECENT ROUNDS'), findsOneWidget);
    expect(store.rounds.length, 2);

    // Target the Dismissible itself: the course name also appears in the
    // summary card, so a text finder can grab the wrong row.
    await tester.drag(find.byType(Dismissible).first, const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(store.rounds.length, 1, reason: 'the swipe should delete the round');
    // The list is newest first, so the tile swiped was r2 and r2 is the one
    // that should be gone.
    expect(store.rounds.single.id, 'r1');
  });

  testWidgets('a deleted round does not come back on rebuild', (tester) async {
    final store = _store([_round('r1', 0), _round('r2', 1)]);
    await tester.pumpWidget(MaterialApp(home: HomePage(store: store)));
    await tester.pumpAndSettle();

    await scrollToRounds(tester);
    // Target the Dismissible itself: the course name also appears in the
    // summary card, so a text finder can grab the wrong row.
    await tester.drag(find.byType(Dismissible).first, const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(store.rounds.length, 1);

    // Rebuild from scratch, the way relaunching the app would.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(MaterialApp(home: HomePage(store: store)));
    await tester.pumpAndSettle();
    expect(store.rounds.length, 1);
  });

  group('par on the recent rounds row', () {
    // The store's White tee is eighteen par 4s, so par 72.
    test('an eighteen hole round is scored against the full par', () {
      final store = _store([_round('r1', 0)]);
      expect(teeFactsFor(store, store.rounds.single).par, 72);
    });

    test('a nine is scored against those nine, not half of 72', () {
      final store = _store([]);
      final nine = Round(
        id: 'r9',
        courseId: 'c1',
        teeId: 'tee-White',
        playedAt: DateTime(2026, 9, 20),
        startHole: 4,
        holes: [for (var i = 0; i < 9; i++) HoleScore(score: 4)],
      );
      expect(nine.holes.length, 9);
      expect(teeFactsFor(store, nine).par, 36);
    });

    test('a round whose tee is gone still gets a plausible par', () {
      final store = _store([]);
      final orphan = Round(
        id: 'rx',
        courseId: 'c1',
        teeId: 'tee-deleted',
        playedAt: DateTime(2026, 9, 20),
        holes: [for (var i = 0; i < 18; i++) HoleScore(score: 4)],
      );
      expect(teeFactsFor(store, orphan).par, 72);
    });

    test('the tee rating and slope come off the round\'s own tee', () {
      final store = _store([_round('r1', 0)]);
      final facts = teeFactsFor(store, store.rounds.single);
      expect(facts.rating, 71.2);
      expect(facts.slope, 124);
    });

    test('a missing tee reports no rating and no slope, not zeroes', () {
      final store = _store([]);
      final orphan = Round(
        id: 'rx',
        courseId: 'c1',
        teeId: 'tee-deleted',
        playedAt: DateTime(2026, 9, 20),
        holes: [for (var i = 0; i < 18; i++) HoleScore(score: 4)],
      );
      final facts = teeFactsFor(store, orphan);
      expect(facts.rating, isNull);
      expect(facts.slope, isNull);
    });

    testWidgets('the row carries the date, the par and the to-par figure', (
      tester,
    ) async {
      final store = _store([_round('r1', 0)]);
      await tester.pumpWidget(MaterialApp(home: HomePage(store: store)));
      await tester.pumpAndSettle();
      await scrollToRounds(tester);

      // 18 fours is a 72, level with a par 72.
      expect(find.textContaining('Par 72'), findsOneWidget);
      expect(find.text('E'), findsOneWidget);
      // Date and tee facts use separate lines so neither is clipped.
      expect(find.text('09-20-26'), findsOneWidget);
      expect(
        find.textContaining('Par 72 • Rating 71.2 • Slope 124'),
        findsOneWidget,
      );
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghin_golf/main.dart';
import 'package:ghin_golf/models.dart';
import 'package:ghin_golf/store.dart';

Course course({String id = 'c1'}) => Course(
  id: id,
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
          HoleInfo(number: i + 1, par: 4, yardage: 410, strokeIndex: i + 1),
      ],
    ),
  ],
);

Round round(
  String id, {
  int score = 4,
  int day = 0,
  double? handicapIndexAtPlay,
  int? courseHandicap,
}) => Round(
  id: id,
  courseId: 'c1',
  teeId: 'tee-White',
  playedAt: DateTime.utc(2026, 9, 20).add(Duration(days: day)),
  holes: [for (var i = 0; i < 18; i++) HoleScore(score: score, putts: 2)],
  handicapIndexAtPlay: handicapIndexAtPlay,
  courseHandicap: courseHandicap,
);

GolfStore storeWith(List<Round> rounds) => GolfStore()
  ..rounds = rounds
  ..courses = [course()];

Future<void> scrollToRounds(WidgetTester tester) async {
  await tester.drag(find.byType(ListView), const Offset(0, -700));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byType(Dismissible).first);
  await tester.pumpAndSettle();
}

/// The save button sits at the foot of the entry screen, below the score
/// strip, so it has to be scrolled to before it can be tapped.
Future<void> tapUpdate(WidgetTester tester) async {
  await tester.dragUntilVisible(
    find.textContaining('total'),
    find.byType(ListView).last,
    const Offset(0, -300),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('total').last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('tapping a round opens it for editing', (tester) async {
    final store = storeWith([round('r1', score: 4, day: 1)]);
    await tester.pumpWidget(MaterialApp(home: HomePage(store: store)));
    await tester.pumpAndSettle();
    await scrollToRounds(tester);

    await tester.tap(find.byType(Dismissible).first);
    await tester.pumpAndSettle();

    expect(find.text('Edit Round'), findsOneWidget);
  });

  testWidgets('the editor starts from the scores already posted', (
    tester,
  ) async {
    final store = storeWith([round('r1', score: 6, day: 1)]);
    await tester.pumpWidget(MaterialApp(home: HomePage(store: store)));
    await tester.pumpAndSettle();
    await scrollToRounds(tester);

    await tester.tap(find.byType(Dismissible).first);
    await tester.pumpAndSettle();

    // 18 holes of 6 is 108, so the button offers to update that, not a fresh
    // round built from par.
    await tester.dragUntilVisible(
      find.text('Update 108 total'),
      find.byType(ListView).last,
      const Offset(0, -300),
    );
    expect(find.text('Update 108 total'), findsOneWidget);
  });

  testWidgets('saving an edit changes the round instead of adding one', (
    tester,
  ) async {
    final store = storeWith([round('r1', score: 4, day: 1)]);
    await tester.pumpWidget(MaterialApp(home: HomePage(store: store)));
    await tester.pumpAndSettle();
    await scrollToRounds(tester);
    await tester.tap(find.byType(Dismissible).first);
    await tester.pumpAndSettle();

    await tapUpdate(tester);

    expect(store.rounds.length, 1, reason: 'an edit must not post a second');
    expect(store.rounds.single.totalGross, 72);
  });

  testWidgets('changing the date saves and returns to Home', (tester) async {
    final store = storeWith([round('r1', score: 4, day: 5)]);
    await tester.pumpWidget(MaterialApp(home: HomePage(store: store)));
    await tester.pumpAndSettle();
    await scrollToRounds(tester);
    await tester.tap(find.byType(Dismissible).first);
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('edit-round-date')),
        matching: find.text('Change'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('24').last);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tapUpdate(tester);

    expect(store.rounds.single.playedAt.month, 9);
    expect(store.rounds.single.playedAt.day, 24);
    expect(find.byType(HomePage), findsOneWidget);
    expect(find.byType(PostPage), findsNothing);
  });

  testWidgets('an edit keeps the round id, date and handicap snapshot', (
    tester,
  ) async {
    final original = round('r1', score: 4, day: 5);
    final store = storeWith([original]);
    await tester.pumpWidget(MaterialApp(home: HomePage(store: store)));
    await tester.pumpAndSettle();
    await scrollToRounds(tester);
    await tester.tap(find.byType(Dismissible).first);
    await tester.pumpAndSettle();
    await tapUpdate(tester);

    final after = store.rounds.single;
    expect(after.id, original.id);
    expect(after.playedAt, original.playedAt);
    expect(after.handicapIndexAtPlay, original.handicapIndexAtPlay);
  });

  for (final index in [0.0, -2.0]) {
    testWidgets('editing a $index index preserves the snapshot', (
      tester,
    ) async {
      final original = round(
        'r1',
        score: 4,
        day: 5,
        handicapIndexAtPlay: index,
        courseHandicap: 0,
      );
      final store = storeWith([original]);
      await tester.pumpWidget(MaterialApp(home: HomePage(store: store)));
      await tester.pumpAndSettle();
      await scrollToRounds(tester);
      await tester.tap(find.byType(Dismissible).first);
      await tester.pumpAndSettle();
      await tapUpdate(tester);

      expect(store.rounds.single.handicapIndexAtPlay, index);
    });
  }

  testWidgets('abandoning an edit leaves the round untouched', (tester) async {
    final store = storeWith([round('r1', score: 4, day: 1)]);
    await tester.pumpWidget(MaterialApp(home: HomePage(store: store)));
    await tester.pumpAndSettle();
    await scrollToRounds(tester);
    await tester.tap(find.byType(Dismissible).first);
    await tester.pumpAndSettle();

    // The editor works on copies; walking away must not have saved anything.
    expect(store.rounds.single.totalGross, 72);
    expect(store.rounds.length, 1);
  });

  testWidgets('changing a score then backing out does not touch the round', (
    tester,
  ) async {
    // The editor must not be holding the live HoleScore objects: the store's
    // round would change under it the moment a score is tapped, with no save.
    final store = storeWith([round('r1', score: 4, day: 1)]);
    await tester.pumpWidget(MaterialApp(home: HomePage(store: store)));
    await tester.pumpAndSettle();
    await scrollToRounds(tester);
    await tester.tap(find.byType(Dismissible).first);
    await tester.pumpAndSettle();

    // Bump the first hole up a stroke, then leave without saving.
    await tester.ensureVisible(find.byIcon(Icons.add).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pumpAndSettle();
    expect(
      store.rounds.single.holes.first.score,
      4,
      reason: 'the stored round must not change before saving',
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(store.rounds.single.totalGross, 72);
  });

  testWidgets('there is a visible delete control on every round', (
    tester,
  ) async {
    final store = storeWith([round('r1', day: 1), round('r2', day: 0)]);
    await tester.pumpWidget(MaterialApp(home: HomePage(store: store)));
    await tester.pumpAndSettle();
    await scrollToRounds(tester);

    // Delete remains directly accessible; edit is performed by tapping the row.
    expect(find.byTooltip('Delete round'), findsNWidgets(2));
    expect(find.byTooltip('Edit round'), findsNothing);
  });

  testWidgets('the delete button removes the round and offers undo', (
    tester,
  ) async {
    final store = storeWith([round('r1', day: 1), round('r2', day: 0)]);
    await tester.pumpWidget(MaterialApp(home: HomePage(store: store)));
    await tester.pumpAndSettle();
    await scrollToRounds(tester);

    await tester.tap(find.byTooltip('Delete round').first);
    await tester.pumpAndSettle();

    expect(store.rounds.length, 1);
    expect(find.text('Undo'), findsOneWidget);
  });

  testWidgets('undo puts the round back where it was', (tester) async {
    final store = storeWith([
      round('r1', day: 3),
      round('r2', day: 2),
      round('r3', day: 1),
    ]);
    await tester.pumpWidget(MaterialApp(home: HomePage(store: store)));
    await tester.pumpAndSettle();
    await scrollToRounds(tester);

    // The list is newest first, so the first delete button is r1 at index 0.
    await tester.tap(find.byTooltip('Delete round').first);
    await tester.pumpAndSettle();
    expect(store.rounds.map((r) => r.id), ['r2', 'r3']);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(store.rounds.map((r) => r.id), ['r1', 'r2', 'r3']);
  });

  testWidgets('the swipe still deletes, and can be undone too', (tester) async {
    final store = storeWith([round('r1', day: 1), round('r2', day: 0)]);
    await tester.pumpWidget(MaterialApp(home: HomePage(store: store)));
    await tester.pumpAndSettle();
    await scrollToRounds(tester);

    await tester.drag(find.byType(Dismissible).first, const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(store.rounds.length, 1);
    expect(find.text('Undo'), findsOneWidget);
  });
}

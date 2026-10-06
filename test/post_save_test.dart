import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ghin_golf/main.dart';
import 'package:ghin_golf/models.dart';
import 'package:ghin_golf/store.dart';
import 'package:ghin_golf/whs.dart' as whs;

void main() {
  testWidgets('saving a round resets scores to par for the same course', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = GolfStore();
    await tester.pumpWidget(MaterialApp(home: PostPage(store: store)));
    await tester.pumpAndSettle();

    // Crystal Lake is par 71; bogey the first hole so the reset is visible.
    expect(find.text('Save 71 total'), findsOneWidget);
    final bogey = find.text('Bogey');
    await tester.ensureVisible(bogey);
    await tester.pumpAndSettle();
    await tester.tap(bogey);
    await tester.pumpAndSettle();
    expect(find.text('Save 72 total'), findsOneWidget);

    final save = find.text('Save 72 total');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    // The posted round keeps the entered scores; the card resets to par.
    expect(store.rounds.length, 1);
    expect(store.rounds.single.totalGross, 72);
    expect(find.text('Save 71 total'), findsOneWidget);
  });

  testWidgets('play page offers Save Scorecard above the save button', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = GolfStore();
    await tester.pumpWidget(MaterialApp(home: PostPage(store: store)));
    await tester.pumpAndSettle();

    final photo = find.byKey(const ValueKey('play-save-scorecard'));
    expect(photo, findsOneWidget);
    expect(find.text('Save Scorecard'), findsOneWidget);
    final save = find.text('Save 71 total');
    expect(tester.getCenter(photo).dy, lessThan(tester.getCenter(save).dy));

    await tester.ensureVisible(photo);
    await tester.pumpAndSettle();
    await tester.tap(photo);
    await tester.pumpAndSettle();
    expect(find.text('Take photo'), findsOneWidget);
    expect(find.text('Choose from gallery'), findsOneWidget);
  });

  testWidgets('Play holes selector only offers 9 and 18 holes', (tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = GolfStore();
    await tester.pumpWidget(MaterialApp(home: PostPage(store: store)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('play-hole-count-selector')));
    await tester.pumpAndSettle();
    expect(find.text('9 Holes'), findsWidgets);
    expect(find.text('18 Holes'), findsWidgets);
    expect(find.text('10 Holes'), findsNothing);
    expect(find.text('17 Holes'), findsNothing);
  });

  testWidgets('quick entry score chips lay out three per row at equal width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = GolfStore();
    await tester.pumpWidget(MaterialApp(home: PostPage(store: store)));
    await tester.pumpAndSettle();

    Finder chipOf(String label) => find.widgetWithText(ScorePill, label);
    Material pillMaterial(String label) => tester.widget<Material>(
      find.descendant(of: chipOf(label), matching: find.byType(Material)),
    );
    const labels = ['Eagle', 'Birdie', 'Par', 'Bogey', 'Double', 'Triple'];
    final centers = [for (final l in labels) tester.getCenter(chipOf(l))];
    final widths = [for (final l in labels) tester.getSize(chipOf(l)).width];
    // Two rows of three.
    for (final c in centers.take(3).skip(1)) {
      expect((c.dy - centers.first.dy).abs(), lessThan(1));
    }
    for (final c in centers.skip(3)) {
      expect((c.dy - centers[3].dy).abs(), lessThan(1));
    }
    expect(centers[3].dy, greaterThan(centers.first.dy + 1));
    // Every pill the same width.
    for (final w in widths.skip(1)) {
      expect((w - widths.first).abs(), lessThan(1));
    }
    // Every pill an oval with the same outline width.
    for (final l in labels) {
      final shape = pillMaterial(l).shape;
      expect(shape, isA<StadiumBorder>());
      expect((shape as StadiumBorder).side.width, 2);
    }
    // Same height on all six.
    final heights = [for (final l in labels) tester.getSize(chipOf(l)).height];
    for (final h in heights.skip(1)) {
      expect((h - heights.first).abs(), lessThan(1));
    }
  });

  testWidgets('quick entry score pills show no checkmark', (tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = GolfStore();
    await tester.pumpWidget(MaterialApp(home: PostPage(store: store)));
    await tester.pumpAndSettle();

    expect(find.byType(ScorePill), findsNWidgets(6));
    for (final l in ['Eagle', 'Birdie', 'Par', 'Bogey', 'Double', 'Triple']) {
      expect(
        find.descendant(
          of: find.widgetWithText(ScorePill, l),
          matching: find.byType(Icon),
        ),
        findsNothing,
      );
    }
  });

  testWidgets('hole header popup enters a score past triple', (tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = GolfStore();
    await tester.pumpWidget(MaterialApp(home: PostPage(store: store)));
    await tester.pumpAndSettle();

    final header = find.byKey(const ValueKey('play-hole-header'));
    await tester.ensureVisible(header);
    await tester.pumpAndSettle();
    await tester.tap(header);
    await tester.pumpAndSettle();
    expect(find.text('Hole 1'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '11');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('play-hole-score-0')),
        matching: find.text('11'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('hole header popup cancel keeps the score', (tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = GolfStore();
    await tester.pumpWidget(MaterialApp(home: PostPage(store: store)));
    await tester.pumpAndSettle();

    final header = find.byKey(const ValueKey('play-hole-header'));
    await tester.ensureVisible(header);
    await tester.pumpAndSettle();
    await tester.tap(header);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '11');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Hole 1'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('play-hole-score-0')),
        matching: find.text('11'),
      ),
      findsNothing,
    );
  });

  testWidgets('hole header popup rejects out-of-range scores', (tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = GolfStore();
    await tester.pumpWidget(MaterialApp(home: PostPage(store: store)));
    await tester.pumpAndSettle();

    final header = find.byKey(const ValueKey('play-hole-header'));
    await tester.ensureVisible(header);
    await tester.pumpAndSettle();
    await tester.tap(header);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '13');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a score from 1 to 12.'), findsOneWidget);
    expect(find.text('Hole 1'), findsOneWidget);
  });

  testWidgets('saving caps holes at par plus five while establishing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // No rounds yet, so no Handicap Index: the establishing cap applies.
    final store = GolfStore();
    await tester.pumpWidget(MaterialApp(home: PostPage(store: store)));
    await tester.pumpAndSettle();

    final tee = store.alphabeticalCourses.first.defaultTee;
    final parSum = tee.holes.fold(0, (s, h) => s + h.par);
    final par1 = tee.holes.first.par;

    // Blow up hole 1 past any cap, then save.
    final header = find.byKey(const ValueKey('play-hole-header'));
    await tester.ensureVisible(header);
    await tester.pumpAndSettle();
    await tester.tap(header);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '12');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final save = find.text('Save ${parSum - par1 + 12} total');
    await tester.scrollUntilVisible(
      save,
      100,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('play-page-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(store.rounds.single.holes[0].score, par1 + 5);
    expect(store.rounds.single.totalGross, parSum + 5);
    expect(find.textContaining('capped at max'), findsOneWidget);
  });

  testWidgets('saving scrolls hole 1 back into view', (tester) async {
    // Short enough that both the strip and the page must scroll.
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = GolfStore();
    await tester.pumpWidget(MaterialApp(home: PostPage(store: store)));
    await tester.pumpAndSettle();

    // Play through to the far end, then scroll down to save.
    for (var i = 0; i < 17; i++) {
      await tester.tap(find.text('Next >'));
      await tester.pumpAndSettle();
    }
    final save = find.text('Save 71 total');
    // scrollUntilVisible, not ensureVisible: the page is a lazy ListView and
    // the save button starts unbuilt below the fold in this viewport.
    await tester.scrollUntilVisible(
      save,
      100,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('play-page-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    final firstChip = find.byKey(const ValueKey('play-hole-chip-0'));
    final screen =
        Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);
    expect(screen.contains(tester.getCenter(firstChip)), isTrue);
  });

  testWidgets('editing a round with a photo offers viewing and removal', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tmp = Directory.systemTemp.createTempSync('ghin_edit_photo');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final photo = File('${tmp.path}/r1.png')
      ..writeAsBytesSync(
        File(
          'android/app/src/main/res/mipmap-mdpi/ic_launcher.png',
        ).readAsBytesSync(),
      );
    final store = GolfStore();
    final seed = store.courseById('crystal-lake')!;
    store.rounds = [
      Round(
        id: 'r1',
        courseId: seed.id,
        teeId: seed.defaultTee.id,
        playedAt: DateTime(2026, 9, 20),
        holes: [for (var i = 0; i < 18; i++) HoleScore(score: 4, putts: 2)],
        imagePath: photo.path,
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: PostPage(store: store, existing: store.rounds.single),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Scorecard photo attached'), findsOneWidget);
    final remove = find.byKey(const ValueKey('edit-round-remove-photo'));
    await tester.ensureVisible(remove);
    await tester.pumpAndSettle();
    await tester.tap(remove);
    await tester.pumpAndSettle();

    expect(photo.existsSync(), isFalse);
    expect(find.text('No scorecard photo'), findsOneWidget);

    final save = find.text('Update 72 total');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(store.rounds.single.imagePath, isEmpty);
  });

  testWidgets('editing a round without a photo offers adding one', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = GolfStore();
    final seed = store.courseById('crystal-lake')!;
    store.rounds = [
      Round(
        id: 'r1',
        courseId: seed.id,
        teeId: seed.defaultTee.id,
        playedAt: DateTime(2026, 9, 20),
        holes: [for (var i = 0; i < 18; i++) HoleScore(score: 4, putts: 2)],
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: PostPage(store: store, existing: store.rounds.single),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No scorecard photo'), findsOneWidget);
    final add = find.byKey(const ValueKey('edit-round-add-photo'));
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(find.text('Take photo'), findsOneWidget);
    expect(find.text('Choose from gallery'), findsOneWidget);
  });

  testWidgets('posting a new round shows no photo section', (tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: PostPage(store: GolfStore())));
    await tester.pumpAndSettle();

    expect(find.text('No scorecard photo'), findsNothing);
    expect(find.text('Scorecard photo attached'), findsNothing);
  });

  testWidgets('an entered PCC is stored on the round and feeds the score', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = GolfStore();
    await tester.pumpWidget(MaterialApp(home: PostPage(store: store)));
    await tester.pumpAndSettle();

    // Pick +0.5 from the PCC dropdown, then save par up the middle.
    final pcc = find.byKey(const ValueKey('play-pcc-selector'));
    await tester.ensureVisible(pcc);
    await tester.pumpAndSettle();
    await tester.tap(pcc);
    await tester.pumpAndSettle();
    await tester.tap(find.text('+0.5').last);
    await tester.pumpAndSettle();

    final save = find.text('Save 71 total');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(store.rounds.single.pcc, 0.5);
    // A +0.5 PCC makes the round half a stroke worse for handicap purposes.
    final tee = store.alphabeticalCourses.first.defaultTee;
    final expected = whs.scoreDifferential(
      adjustedGrossScore: 71, // par total; nothing caps a four
      courseRating: tee.rating,
      slopeRating: tee.slope.toDouble(),
      pcc: 0.5,
    );
    expect(store.rounds.single.differential(tee), closeTo(expected, 0.001));
  });
}

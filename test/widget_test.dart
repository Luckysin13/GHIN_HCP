import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ghin_golf/app_theme.dart';
import 'package:ghin_golf/design_tokens.dart';
import 'package:ghin_golf/ghin_brand_mark.dart';
import 'package:ghin_golf/main.dart';
import 'package:ghin_golf/models.dart';
import 'package:ghin_golf/store.dart';
import 'package:ghin_golf/whs.dart' as whs;

void main() {
  // The default test surface is 800x600, which is shorter than the Home page
  // and puts the quick-post card's controls behind the bottom navigation bar,
  // where a tap cannot reach them. These tests use a tall window so the whole
  // card is laid out and hit-testable at once.
  Future<void> pumpTallHome(WidgetTester tester, GolfStore store) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(GhinApp(store: store));
    await tester.pumpAndSettle();
  }

  Future<void> chooseHoleCount(
    WidgetTester tester, {
    required String selectorKey,
    required int count,
  }) async {
    await tester.tap(find.byKey(ValueKey(selectorKey)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('$count Holes').last);
    await tester.pumpAndSettle();
  }

  testWidgets('GHIN app boots to Home with handicap card', (tester) async {
    final store = GolfStore();
    await tester.pumpWidget(GhinApp(store: store));
    expect(find.text('HANDICAP INDEX'), findsOneWidget);
    expect(find.byType(GhinBrandMark), findsOneWidget);
    expect(find.text('GHIN HCP'), findsOneWidget);
    expect(find.text('YOUR GAME, AT A GLANCE'), findsNothing);
    expect(find.text('Handicap and recent play'), findsNothing);
    expect(find.text('No previous score at this course'), findsOneWidget);
    // Quick posting is the only route from Home now: the shortcut buttons to
    // the Play and Courses tabs are gone, so the card must be present here.
    expect(find.text('Quick score'), findsOneWidget);
    expect(find.text('Post Score'), findsNothing);
    expect(find.text('Find Course'), findsNothing);
    // The per-hole par row is gone too, so no "P1 4" style labels on Home.
    expect(find.textContaining(RegExp(r'^P\d+ ')), findsNothing);
  });

  testWidgets('Quick post opens on the White tee, not the longest one', (
    tester,
  ) async {
    final store = GolfStore();
    await pumpTallHome(tester, store);

    // The seed tee list runs longest first, so a tees.first default would show
    // Black here. White is the tee most golfers actually play.
    expect(store.courses.first.tees.first.name, 'Black');
    expect(store.courses.first.defaultTee.name, 'White');
    expect(find.textContaining('White •'), findsOneWidget);
    expect(find.textContaining('Black •'), findsNothing);
    expect(find.text('Enter your total'), findsNothing);
    final teeSelector = find.byType(DropdownButtonFormField<String>).at(1);
    final holeSelector = find.byKey(const ValueKey('home-hole-count-selector'));
    expect(
      tester.getTopLeft(holeSelector).dy -
          tester.getBottomRight(teeSelector).dy,
      greaterThanOrEqualTo(8),
    );
  });

  testWidgets('Home and Play show tees as name • rating/slope • Par ##', (
    tester,
  ) async {
    final store = GolfStore();
    await pumpTallHome(tester, store);

    final tee = store.courses.first.defaultTee;
    String label(Tee t) =>
        '${t.name} • ${t.rating.toStringAsFixed(1)}/${t.slope} • Par ${t.par}';

    // Home QuickPost tee selector carries the same format as the Courses page.
    expect(find.text(label(tee)), findsOneWidget);

    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();

    // The Play tee selector shows the identical label before opening...
    expect(find.text(label(tee)), findsOneWidget);

    // ...and every option in the dropdown does too.
    await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
    await tester.pumpAndSettle();
    for (final t in store.courses.first.tees) {
      expect(find.text(label(t)), findsWidgets, reason: label(t));
    }
  });

  testWidgets('Home and Play course dropdowns are alphabetically sorted', (
    tester,
  ) async {
    final store = GolfStore();
    final tee = store.courses.first.defaultTee;
    store.courses = [
      for (final name in ['Zeta Course', 'Alpha Course', 'Middle Course'])
        Course(
          id: name.toLowerCase().replaceAll(' ', '-'),
          name: name,
          city: '',
          state: '',
          tees: [tee],
        ),
    ];
    const expected = ['Alpha Course', 'Middle Course', 'Zeta Course'];

    Future<void> expectSortedCourseMenu() async {
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      final yPositions = [
        for (final name in expected) tester.getCenter(find.text(name).last).dy,
      ];
      expect(yPositions, orderedEquals(yPositions.toList()..sort()));
      await tester.tap(find.text('Alpha Course').last);
      await tester.pumpAndSettle();
    }

    await pumpTallHome(tester, store);
    await expectSortedCourseMenu();

    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();
    await expectSortedCourseMenu();
  });

  testWidgets('Play course and tee card matches Home quick score padding', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(GhinApp(store: GolfStore()));
    await tester.pumpAndSettle();

    final homeList = tester.widget<ListView>(find.byType(ListView).first);
    final homeQuickCard = find.ancestor(
      of: find.text('Quick score'),
      matching: find.byType(Card),
    );
    final homeCardPadding = tester.widget<Padding>(
      find
          .descendant(
            of: homeQuickCard,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Padding &&
                  widget.padding == const EdgeInsets.all(12),
            ),
          )
          .first,
    );
    expect(homeList.padding, const EdgeInsets.all(Insets.gutter));
    expect(homeCardPadding.padding, const EdgeInsets.all(12));

    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();

    final playList = tester.widget<ListView>(find.byType(ListView).first);
    final playCardPadding = tester.widget<Padding>(
      find
          .descendant(
            of: find.byType(Card).first,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Padding &&
                  widget.padding == const EdgeInsets.all(12),
            ),
          )
          .first,
    );
    expect(playList.padding, homeList.padding);
    expect(playCardPadding.padding, homeCardPadding.padding);
    final teeSelector = find.byType(DropdownButtonFormField<String>).at(1);
    final holeSelector = find.byKey(const ValueKey('play-hole-count-selector'));
    expect(
      tester.widget<DropdownButtonFormField<int>>(holeSelector).initialValue,
      18,
    );
    expect(
      tester.getTopLeft(holeSelector).dy -
          tester.getBottomRight(teeSelector).dy,
      greaterThanOrEqualTo(8),
    );
    expect(
      tester.getCenter(holeSelector).dx,
      closeTo(
        tester.view.physicalSize.width / tester.view.devicePixelRatio / 2,
        1,
      ),
    );
  });

  testWidgets('Play score entry uses the hole score-vs-par color scheme', (
    tester,
  ) async {
    final store = GolfStore();
    await tester.pumpWidget(GhinApp(store: store));
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();
    expect(find.text('Hole 1 • Par 4'), findsOneWidget);
    final holeTitle = tester.widget<Text>(find.text('Hole 1 • Par 4'));
    final titleSpans = (holeTitle.textSpan as TextSpan).children!;
    expect(titleSpans[0].style?.fontSize, 22);
    expect(titleSpans[1].style?.fontSize, 14);
    final selectedHole = tester.widget<Container>(
      find.byKey(const ValueKey('play-hole-chip-0')),
    );
    final selectedHoleDecoration = selectedHole.decoration as BoxDecoration;
    expect(
      (selectedHoleDecoration.border as Border).top.color,
      AppTheme.light.colorScheme.primary,
    );
    expect((selectedHoleDecoration.border as Border).top.width, 3);
    expect(find.text('Hole 1 of 18'), findsNothing);
    expect(find.text('< Prev'), findsOneWidget);
    expect(find.text('Next >'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('play-prev-hole')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('play-next-hole')))
          .onPressed,
      isNotNull,
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Text && widget.style?.fontSize == 26,
      ),
      findsNothing,
    );
    // The top three pills share one row at the same width.
    final tops = [
      for (final label in ['Eagle', 'Birdie', 'Par'])
        tester.getCenter(find.widgetWithText(ScorePill, label)),
    ];
    expect((tops[1].dy - tops[0].dy).abs(), lessThan(1));
    expect((tops[2].dy - tops[0].dy).abs(), lessThan(1));
    final topWidths = [
      for (final label in ['Eagle', 'Birdie', 'Par'])
        tester.getSize(find.widgetWithText(ScorePill, label)).width,
    ];
    expect(topWidths[1], topWidths[0]);
    expect(topWidths[2], topWidths[0]);
    for (final label in ['GIR', 'Putts', 'Penalty', 'Fairway']) {
      final controls = find.byKey(
        ValueKey('play-controls-${label.toLowerCase()}'),
      );
      expect(controls, findsOneWidget);
      expect(
        tester.getTopLeft(controls).dx - tester.getTopLeft(find.text(label)).dx,
        greaterThanOrEqualTo(80),
      );
    }
    final holeStrip = find.byWidgetPredicate(
      (widget) =>
          widget is ListView && widget.scrollDirection == Axis.horizontal,
    );
    final currentHoleCard = find.ancestor(
      of: find.text('Hole 1 • Par 4'),
      matching: find.byType(Card),
    );
    expect(
      tester.getTopLeft(currentHoleCard.first).dy -
          tester.getBottomLeft(holeStrip).dy,
      Insets.md,
    );
    final birdieFinder = find.widgetWithText(ScorePill, 'Birdie');
    final birdie = tester.widget<ScorePill>(birdieFinder);
    final birdieColor = Color(store.scoreColorValue(-1));
    expect(birdie.color, birdieColor);
    expect(birdie.selected, isFalse);
    final birdieMat = tester.widget<Material>(
      find.descendant(of: birdieFinder, matching: find.byType(Material)),
    );
    expect(birdieMat.color, birdieColor.withValues(alpha: 0.35));
    expect(
      (birdieMat.shape as StadiumBorder).side.color,
      birdieColor.withValues(alpha: 0.9),
    );
    expect(
      tester
          .widget<Text>(
            find.descendant(of: birdieFinder, matching: find.text('Birdie')),
          )
          .style
          ?.color,
      AppTheme.light.colorScheme.onSurface,
    );
    expect(
      tester.widget<ScorePill>(find.widgetWithText(ScorePill, 'Par')).selected,
      isTrue,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('play-hole-chip-0'))).width,
      54,
    );
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('play-hole-chip-0')),
              matching: find.text('1'),
            ),
          )
          .style
          ?.fontSize,
      22,
    );
    expect(
      tester
          .widget<Container>(find.byKey(const ValueKey('play-hole-score-0')))
          .color,
      const Color(0xFF607D8B),
    );
    expect(
      tester
          .widget<Container>(find.byKey(const ValueKey('play-hole-number-0')))
          .color,
      AppTheme.light.colorScheme.primaryContainer,
    );

    // Birdie the hole (auto-advances), then return to confirm the chip and
    // hole strip still show the recorded score.
    await tester.tap(
      find.byWidgetPredicate((w) => w is ScorePill && w.label == 'Birdie'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hole 2 • Par 4'), findsOneWidget);
    expect(
      tester
          .widget<Container>(find.byKey(const ValueKey('play-hole-score-0')))
          .color,
      const Color(0xFF43A047),
    );
    // Back to hole 1 via its strip chip.
    await tester.tap(find.byKey(const ValueKey('play-hole-chip-0')));
    await tester.pumpAndSettle();
    expect(find.text('Hole 1 • Par 4'), findsOneWidget);

    final birdieChip = tester.widget<ScorePill>(
      find.byWidgetPredicate((w) => w is ScorePill && w.label == 'Birdie'),
    );
    expect(birdieChip.selected, isTrue);
    expect(birdieChip.color, const Color(0xFF43A047));
  });

  testWidgets('Play hole navigation follows the score and stops at both ends', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = GolfStore();
    await tester.pumpWidget(GhinApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();

    final previous = find.byKey(const ValueKey('play-prev-hole'));
    final next = find.byKey(const ValueKey('play-next-hole'));
    final tee = store.courses.first.defaultTee;

    for (var hole = 2; hole <= 18; hole++) {
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(
        find.text('Hole $hole • Par ${tee.holes[hole - 1].par}'),
        findsOneWidget,
      );
    }
    expect(tester.widget<TextButton>(next).onPressed, isNull);
    expect(tester.widget<TextButton>(previous).onPressed, isNotNull);

    await tester.tap(previous);
    await tester.pumpAndSettle();
    expect(find.text('Hole 17 • Par ${tee.holes[16].par}'), findsOneWidget);
  });

  testWidgets('light theme keeps play hole and shot labels readable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: PostPage(store: GolfStore()),
      ),
    );
    await tester.pumpAndSettle();

    final scheme = AppTheme.light.colorScheme;
    expect(
      tester.widget<Text>(find.text('Hole 1 • Par 4')).style?.color,
      scheme.onSurface,
    );
    expect(
      tester.widget<Text>(find.text('GIR')).style?.color,
      scheme.onSurface,
    );
    expect(
      tester.widget<Text>(find.text('Fairway')).style?.color,
      scheme.onSurface,
    );
    expect(
      tester.widget<Text>(find.text('Yes')).style?.color,
      scheme.onSurface,
    );
    expect(
      tester.widget<Text>(find.text('No')).style?.color,
      scheme.onSecondaryContainer,
    );

    for (final direction in ['L', 'H', 'R']) {
      expect(
        tester.widget<Text>(find.text(direction)).style?.color,
        scheme.onSurface,
      );
    }
  });

  testWidgets('light theme shows the Home hole-count dropdown choices', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HomePage(store: GolfStore()),
      ),
    );
    await tester.pumpAndSettle();

    final selector = find.byKey(const ValueKey('home-hole-count-selector'));
    expect(
      tester.widget<DropdownButtonFormField<int>>(selector).initialValue,
      18,
    );
    await tester.tap(selector);
    await tester.pumpAndSettle();
    expect(find.text('9 Holes'), findsWidgets);
    expect(find.text('18 Holes'), findsWidgets);
  });

  testWidgets('Performance no longer advertises driving distance', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: StatsPage(store: GolfStore())));
    expect(
      find.textContaining(RegExp('driving distance', caseSensitive: false)),
      findsNothing,
    );
  });

  testWidgets('Stats groups scores by expandable course and calculates CH', (
    tester,
  ) async {
    final store = GolfStore();
    final tee = Tee(
      id: 'white',
      name: 'White',
      rating: 72,
      slope: 113,
      holes: [
        for (var i = 0; i < 18; i++)
          HoleInfo(number: i + 1, par: 4, yardage: 400, strokeIndex: i + 1),
      ],
    );
    store.courses = [
      Course(
        id: 'north',
        name: 'North Course',
        city: '',
        state: '',
        tees: [tee],
        custom: true,
      ),
      Course(
        id: 'south',
        name: 'South Course',
        city: '',
        state: '',
        tees: [
          Tee(
            id: 'south-white',
            name: 'White',
            rating: 72,
            slope: 113,
            holes: tee.holes,
          ),
        ],
        custom: true,
      ),
    ];
    store.rounds = [
      Round(
        id: 'north-round',
        courseId: 'north',
        teeId: 'white',
        playedAt: DateTime(2026, 9, 20),
        holes: [for (var i = 0; i < 18; i++) HoleScore(score: 5, putts: 2)],
        handicapIndexAtPlay: 12.4,
      ),
      Round(
        id: 'south-round',
        courseId: 'south',
        teeId: 'south-white',
        playedAt: DateTime(2026, 9, 21),
        holes: [for (var i = 0; i < 18; i++) HoleScore(score: 4, putts: 2)],
        courseHandicap: 7,
      ),
    ];
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: StatsPage(store: store)));
    await tester.pumpAndSettle();

    expect(find.text('Courses Played'), findsOneWidget);
    expect(find.text('North Course'), findsOneWidget);
    expect(find.text('South Course'), findsOneWidget);
    expect(find.text('Total: 90 • (F) 45 • (B) 45'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('stats-course-north')));
    await tester.pumpAndSettle();
    expect(find.text('Total: 90 • (F) 45 • (B) 45'), findsOneWidget);
    expect(
      find.text('09/20/2026 • 18 holes • Putts 36 • Pen 0'),
      findsOneWidget,
    );
    expect(find.text('12'), findsOneWidget);
    expect(find.text('Total: 72 • (F) 36 • (B) 36'), findsNothing);

    // The header area, including its subtitle, toggles the whole course group.
    await tester.tap(find.text('North Course'));
    await tester.pumpAndSettle();
    expect(find.text('Total: 90 • (F) 45 • (B) 45'), findsNothing);
  });

  testWidgets('Stats course header shows the WHS course handicap', (
    tester,
  ) async {
    final store = GolfStore();
    final tee = Tee(
      id: 'white',
      name: 'White',
      rating: 72,
      slope: 113,
      holes: [
        for (var i = 0; i < 18; i++)
          HoleInfo(number: i + 1, par: 4, yardage: 400, strokeIndex: i + 1),
      ],
    );
    store.courses = [
      Course(
        id: 'north',
        name: 'North Course',
        city: '',
        state: '',
        tees: [tee],
        custom: true,
      ),
    ];
    store.rounds = [
      Round(
        id: 'north-round-1',
        courseId: 'north',
        teeId: 'white',
        playedAt: DateTime(2026, 9, 20),
        holes: [for (var i = 0; i < 18; i++) HoleScore(score: 5, putts: 2)],
        handicapIndexAtPlay: 12.4,
      ),
      Round(
        id: 'north-round-2',
        courseId: 'north',
        teeId: 'white',
        playedAt: DateTime(2026, 9, 21),
        holes: [for (var i = 0; i < 18; i++) HoleScore(score: 4, putts: 2)],
        courseHandicap: 5,
      ),
      Round(
        id: 'north-round-3',
        courseId: 'north',
        teeId: 'white',
        playedAt: DateTime(2026, 9, 22),
        holes: [for (var i = 0; i < 18; i++) HoleScore(score: 5, putts: 2)],
        handicapIndexAtPlay: 12.4,
      ),
    ];
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: StatsPage(store: store)));
    await tester.pumpAndSettle();

    // One handicap for the course from the live index — not a sum — while
    // the per-round avatars stay exactly as they are.
    final hi = store.handicapIndex!;
    final expected = whs.courseHandicap(
      handicapIndex: hi,
      slopeRating: 113,
      courseRating: 72,
      par: 72,
    );
    expect(find.text('3 rounds • CH $expected'), findsOneWidget);
    expect(find.textContaining('Total CH'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('stats-course-north')));
    await tester.pumpAndSettle();
    expect(find.text('Total: 90 • (F) 45 • (B) 45'), findsWidgets);
    expect(find.text('Total: 72 • (F) 36 • (B) 36'), findsOneWidget);
    expect(find.text('12'), findsWidgets);
    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('Stats course header shows a dash before an index exists', (
    tester,
  ) async {
    final store = GolfStore();
    store.courses = [
      Course(
        id: 'north',
        name: 'North Course',
        city: '',
        state: '',
        tees: [
          Tee(
            id: 'white',
            name: 'White',
            rating: 72,
            slope: 113,
            holes: [
              for (var i = 0; i < 18; i++)
                HoleInfo(
                  number: i + 1,
                  par: 4,
                  yardage: 400,
                  strokeIndex: i + 1,
                ),
            ],
          ),
        ],
        custom: true,
      ),
    ];
    store.rounds = [
      Round(
        id: 'north-round-1',
        courseId: 'north',
        teeId: 'white',
        playedAt: DateTime(2026, 9, 20),
        holes: [for (var i = 0; i < 18; i++) HoleScore(score: 5, putts: 2)],
      ),
    ];
    expect(store.handicapIndex, isNull);
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: StatsPage(store: store)));
    await tester.pumpAndSettle();

    expect(find.text('1 round • CH —'), findsOneWidget);
  });

  testWidgets(
    'Stats avatars backfill from the live index for same-day rounds',
    (tester) async {
      final store = GolfStore();
      final tee = Tee(
        id: 'white',
        name: 'White',
        rating: 72,
        slope: 113,
        holes: [
          for (var i = 0; i < 18; i++)
            HoleInfo(number: i + 1, par: 4, yardage: 400, strokeIndex: i + 1),
        ],
      );
      store.courses = [
        Course(
          id: 'north',
          name: 'North Course',
          city: '',
          state: '',
          tees: [tee],
          custom: true,
        ),
      ];
      // Same calendar day, nothing stored: no round has an index in effect
      // before its own date, but the live index still resolves.
      final day = DateTime(2026, 9, 20);
      store.rounds = [
        for (var n = 0; n < 3; n++)
          Round(
            id: 'north-round-$n',
            courseId: 'north',
            teeId: 'white',
            playedAt: day,
            holes: [for (var i = 0; i < 18; i++) HoleScore(score: 5, putts: 2)],
          ),
      ];
      expect(store.handicapIndexBefore(day), isNull);
      final hi = store.handicapIndex!;
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: StatsPage(store: store)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('stats-course-north')));
      await tester.pumpAndSettle();
      final expected = whs.courseHandicap(
        handicapIndex: hi,
        slopeRating: 113,
        courseRating: 72,
        par: 72,
      );
      expect(find.text('$expected'), findsWidgets);
      expect(find.text('—'), findsNothing);
    },
  );

  testWidgets('Stats avatars halve the tee for nines without split ratings', (
    tester,
  ) async {
    final store = GolfStore();
    // No front/back nine rating or slope: the nine-hole formula has nothing
    // to work with, so the avatar must fall back to half the full tee.
    final tee = Tee(
      id: 'white',
      name: 'White',
      rating: 72,
      slope: 113,
      holes: [
        for (var i = 0; i < 18; i++)
          HoleInfo(number: i + 1, par: 4, yardage: 400, strokeIndex: i + 1),
      ],
    );
    store.courses = [
      Course(
        id: 'north',
        name: 'North Course',
        city: '',
        state: '',
        tees: [tee],
        custom: true,
      ),
    ];
    final day = DateTime(2026, 9, 20);
    HoleScore h(int s) => HoleScore(score: s, putts: 2);
    store.rounds = [
      for (var n = 0; n < 3; n++)
        Round(
          id: 'north-round-$n',
          courseId: 'north',
          teeId: 'white',
          playedAt: day,
          holes: [for (var i = 0; i < 18; i++) h(5)],
        ),
      Round(
        id: 'north-nine',
        courseId: 'north',
        teeId: 'white',
        playedAt: day,
        holes: [for (var i = 0; i < 9; i++) h(5)],
      ),
    ];
    final hi = store.handicapIndex!;
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: StatsPage(store: store)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('stats-course-north')));
    await tester.pumpAndSettle();
    final full = whs.courseHandicap(
      handicapIndex: hi,
      slopeRating: 113,
      courseRating: 72,
      par: 72,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('stats-round-north-nine')),
        matching: find.text('${(full / 2).round()}'),
      ),
      findsOneWidget,
    );
    expect(find.text('—'), findsNothing);
  });

  testWidgets('Stats rounds show a photo icon only when a picture is saved', (
    tester,
  ) async {
    final tmp = Directory.systemTemp.createTempSync('ghin_stats_photo');
    addTearDown(() => tmp.deleteSync(recursive: true));
    // A real decodable PNG: the viewer actually renders these bytes.
    final photo = File('${tmp.path}/r1.png')
      ..writeAsBytesSync(
        File(
          'android/app/src/main/res/mipmap-mdpi/ic_launcher.png',
        ).readAsBytesSync(),
      );
    final store = GolfStore();
    final tee = Tee(
      id: 'white',
      name: 'White',
      rating: 72,
      slope: 113,
      holes: [
        for (var i = 0; i < 18; i++)
          HoleInfo(number: i + 1, par: 4, yardage: 400, strokeIndex: i + 1),
      ],
    );
    store.courses = [
      Course(
        id: 'north',
        name: 'North Course',
        city: '',
        state: '',
        tees: [tee],
        custom: true,
      ),
    ];
    Round round(String id, {String img = ''}) => Round(
      id: id,
      courseId: 'north',
      teeId: 'white',
      playedAt: DateTime(2026, 9, 20),
      holes: [for (var i = 0; i < 18; i++) HoleScore(score: 4, putts: 2)],
      courseHandicap: 7,
      imagePath: img,
    );
    store.rounds = [round('r1', img: photo.path), round('r2')];
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: StatsPage(store: store)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('stats-course-north')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('stats-round-photo-r1')), findsOneWidget);
    expect(find.byKey(const ValueKey('stats-round-photo-r2')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('stats-round-photo-r1')));
    await tester.pumpAndSettle();
    expect(find.text('North Course — scorecard'), findsOneWidget);
  });

  testWidgets('tapping a Stats round opens its edit page', (tester) async {
    final store = GolfStore();
    final tee = Tee(
      id: 'white',
      name: 'White',
      rating: 72,
      slope: 113,
      holes: [
        for (var i = 0; i < 18; i++)
          HoleInfo(number: i + 1, par: 4, yardage: 400, strokeIndex: i + 1),
      ],
    );
    store.courses = [
      Course(
        id: 'north',
        name: 'North Course',
        city: '',
        state: '',
        tees: [tee],
        custom: true,
      ),
    ];
    store.rounds = [
      Round(
        id: 'north-round',
        courseId: 'north',
        teeId: 'white',
        playedAt: DateTime(2026, 9, 20),
        holes: [for (var i = 0; i < 18; i++) HoleScore(score: 5, putts: 2)],
        handicapIndexAtPlay: 12.4,
      ),
    ];
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: StatsPage(store: store)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('stats-course-north')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Total: 90 • (F) 45 • (B) 45'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Round'), findsOneWidget);
  });

  testWidgets('tapping a saved course row selects it, not its editor', (
    tester,
  ) async {
    final store = GolfStore();
    final seed = store.courses.first;
    store.addCourse(
      Course(
        id: 'custom-name-tap',
        name: 'North Course',
        city: 'Austin',
        state: 'TX',
        custom: true,
        tees: [
          Tee(
            id: 'custom-name-tap-white',
            name: 'White',
            rating: seed.defaultTee.rating,
            slope: seed.defaultTee.slope,
            holes: seed.defaultTee.holes,
          ),
        ],
      ),
    );
    await tester.pumpWidget(MaterialApp(home: CoursesPage(store: store)));
    await tester.pumpAndSettle();

    expect(find.text('Search Courses'), findsOneWidget);
    expect(find.textContaining('yours'), findsNothing);

    // Tapping the row selects it for the scorecard below; the editor opens
    // only from the pencil button.
    await tester.tap(find.text('Austin, TX • 1 tee'));
    await tester.pumpAndSettle();
    expect(find.text('Edit course'), findsNothing);

    final scheme = Theme.of(
      tester.element(find.byType(CoursesPage)),
    ).colorScheme;
    Card rowCard(String courseId) => tester.widget<Card>(
      find.ancestor(
        of: find.byKey(ValueKey('course-name-$courseId')),
        matching: find.byType(Card),
      ),
    );
    expect(rowCard('custom-name-tap').color, scheme.primaryContainer);
    expect(rowCard('crystal-lake').color, isNull);
  });

  testWidgets('seeded Crystal Lake course opens in the editor', (tester) async {
    final store = GolfStore();
    await tester.pumpWidget(MaterialApp(home: CoursesPage(store: store)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('edit-course-crystal-lake')));
    await tester.pumpAndSettle();
    expect(find.text('Edit course'), findsOneWidget);
    expect(find.text('Crystal Lake Golf Club'), findsWidgets);
  });

  testWidgets('saving a seeded course keeps it seeded', (tester) async {
    final seed = GolfStore().courseById('crystal-lake')!;
    Course? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                Navigator.of(context)
                    .push<Course>(
                      MaterialPageRoute(
                        builder: (_) => AddCourseScreen(existing: seed),
                      ),
                    )
                    .then((course) => result = course);
              },
              child: const Text('Edit seeded course'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Edit seeded course'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('HOLE 1'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    Finder hcpField(int holeIndex) => find.byWidgetPredicate(
      (widget) =>
          widget is TextFormField &&
          widget.key is ValueKey &&
          (widget.key! as ValueKey).value.toString().endsWith('-$holeIndex'),
    );
    await tester.enterText(hcpField(0), '18');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('HOLE 5'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(hcpField(4), '');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Save changes'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.custom, isFalse);
    expect(result!.tees.first.holes[0].strokeIndex, 18);
    expect(result!.tees.first.holes[4].strokeIndex, isNull);
  });

  testWidgets('adding a course clears and unfocuses the search field', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = GolfStore();
    await tester.pumpWidget(MaterialApp(home: CoursesPage(store: store)));
    await tester.pumpAndSettle();

    final search = find.byKey(const ValueKey('course-search'));
    await tester.enterText(search, 'x');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add manually'));
    await tester.pumpAndSettle();

    Future<void> enterField(String label, String value) async {
      final field = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == label,
      );
      await tester.enterText(field, value);
    }

    await enterField('Course name *', 'New Course');
    await enterField('Rating *', '70.0');
    await enterField('Slope *', '120');
    await enterField('Front 9 rating', '34.5');
    await enterField('Front 9 slope', '118');
    await enterField('Back 9 rating', '35.5');
    await enterField('Back 9 slope', '122');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -1200));
    await tester.pumpAndSettle();
    final save = find.text('Save course');
    expect(save, findsOneWidget);
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    final created = store.courses.singleWhere(
      (course) => course.name == 'New Course',
    );
    expect(created.tees.single.frontNineRating, 34.5);
    expect(created.tees.single.frontNineSlope, 118);
    expect(created.tees.single.backNineRating, 35.5);
    expect(created.tees.single.backNineSlope, 122);
    final searchField = tester.widget<TextField>(search);
    expect(searchField.controller?.text, isEmpty);
    expect(searchField.focusNode?.hasFocus, isFalse);
  });

  testWidgets('score colors are user-editable and stick in the store', (
    tester,
  ) async {
    final store = GolfStore();
    await tester.pumpWidget(GhinApp(store: store));
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.palette_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Score colors'), findsOneWidget);
    expect(find.text('Triple or worse'), findsOneWidget);

    // Open the Birdie row and pick the dark-green swatch (34px circle;
    // the 22px row dot shares the default color, so match by size).
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is ListTile && (w.title as Text?)?.data == 'Birdie',
      ),
    );
    await tester.pumpAndSettle();
    const pick = Color(0xFF1B5E20);
    final dots = find.byWidgetPredicate(
      (w) => w is Container && (w.decoration as BoxDecoration?)?.color == pick,
    );
    expect(dots, findsNWidgets(2));
    for (var i = 0; i < dots.evaluate().length; i++) {
      if (tester.getSize(dots.at(i)) == const Size(34, 34)) {
        await tester.tap(dots.at(i));
        break;
      }
    }
    await tester.pumpAndSettle();
    expect(store.scoreColorValue(-1), 0xFF1B5E20);
  });

  testWidgets('OCR inspector shows the raw read text', (tester) async {
    const stub = 'BLUE 402 515 178\nPAR 4 5 3';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: OcrTextDialog(text: stub)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('What the scan read'), findsOneWidget);
    expect(find.text(stub), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('What the scan read'), findsNothing);
  });

  testWidgets('scorecard cells are centered with hole separators', (
    tester,
  ) async {
    final course = GolfStore().courses.first;
    final originalTee = course.tees.first;
    final tee = Tee(
      id: originalTee.id,
      name: originalTee.name,
      rating: originalTee.rating,
      slope: originalTee.slope,
      frontNineRating: originalTee.frontNineRating,
      frontNineSlope: originalTee.frontNineSlope,
      backNineRating: originalTee.backNineRating,
      backNineSlope: originalTee.backNineSlope,
      holes: [
        for (var i = 0; i < originalTee.holes.length; i++)
          HoleInfo(
            number: i + 1,
            par: originalTee.holes[i].par,
            yardage: originalTee.holes[i].yardage,
            strokeIndex: i == 0 ? null : originalTee.holes[i].strokeIndex,
          ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: scorecardTable(course, tee))),
    );
    await tester.pumpAndSettle();
    expect(find.text('FRONT 9'), findsOneWidget);
    expect(find.text('BACK 9'), findsOneWidget);
    expect(find.text('HCP'), findsNWidgets(2));
    expect(find.text('-'), findsOneWidget);
    expect(find.textContaining('Rating 70.4 • Slope 139'), findsOneWidget);
    // Every hole number cell is centered.
    final one = tester.widget<Text>(find.text('1').first);
    expect(one.textAlign, TextAlign.center);
    // Separators: non-last cells carry a right border.
    final seps = find.byWidgetPredicate(
      (w) =>
          w is Container &&
          (w.decoration as BoxDecoration?)?.border is Border &&
          ((w.decoration as BoxDecoration).border as Border).right !=
              BorderSide.none,
    );
    expect(seps, findsWidgets);
  });

  testWidgets('add-course form has no SI controls', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AddCourseScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Add local course'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(find.textContaining(RegExp(r'\bSI\b')), findsNothing);
    expect(find.text('Par: 4'), findsWidgets);
    expect(find.text('Yds'), findsNothing);
  });

  testWidgets('course form Holes and Yardages chips show no checkmark', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: AddCourseScreen()));
    await tester.pumpAndSettle();

    final chips = tester
        .widgetList<ChoiceChip>(find.byType(ChoiceChip))
        .toList();
    expect(chips, isNotEmpty);
    for (final chip in chips) {
      expect(chip.showCheckmark, isFalse);
    }
  });

  testWidgets('saved scorecard photo stays pinned while course form scrolls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final photo = File(
      'android/app/src/main/res/mipmap-mdpi/ic_launcher.png',
    ).absolute;
    expect(photo.existsSync(), isTrue);
    final course = Course(
      id: 'photo-course',
      name: 'Crystal Lake Golf Club',
      city: '',
      state: '',
      imagePath: photo.path,
      tees: [
        Tee(
          id: 'white',
          name: 'White',
          rating: 71.2,
          slope: 124,
          holes: [
            for (var i = 0; i < 18; i++)
              HoleInfo(number: i + 1, par: 4, yardage: 400, strokeIndex: i + 1),
          ],
        ),
      ],
      custom: true,
    );
    await tester.pumpWidget(
      MaterialApp(home: AddCourseScreen(existing: course)),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'initial pinned layout');

    final pinnedPhoto = find.byKey(const ValueKey('pinned-scorecard-photo'));
    expect(find.text('Saved scorecard photo'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('course-scorecard-interactive-viewer')),
      findsOneWidget,
    );
    final image = find.byType(Image).first;
    expect(tester.widget<Image>(image).fit, BoxFit.contain);
    expect(tester.getSize(image).width, greaterThan(200));
    expect(tester.getSize(image).height, greaterThan(140));
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pumpAndSettle();
    expect(find.text('150%'), findsOneWidget);
    await tester.tap(find.byTooltip('Reset zoom and pan'));
    await tester.pumpAndSettle();
    expect(find.text('100%'), findsOneWidget);
    final initialTop = tester.getTopLeft(pinnedPhoto).dy;
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();

    expect(pinnedPhoto, findsOneWidget);
    expect(tester.getTopLeft(pinnedPhoto).dy, initialTop);
    expect(tester.takeException(), isNull);
  });

  testWidgets('quick post selects a playable count for a nine-hole tee', (
    tester,
  ) async {
    final store = GolfStore();
    final seed = store.courses.first;
    store.addCourse(
      Course(
        id: 'short-tee-course',
        name: 'Nine Hole Place',
        city: seed.city,
        state: seed.state,
        custom: true,
        tees: [
          Tee(
            id: 'short-tee',
            name: 'Nine Hole Tee',
            rating: seed.tees.first.rating,
            slope: seed.tees.first.slope,
            holes: seed.tees.first.holes.take(9).toList(),
          ),
        ],
      ),
    );
    await pumpTallHome(tester, store);

    // Selecting a 9-hole course adapts the hole-count field to its tee.
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nine Hole Place').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Nine Hole Tee •'), findsOneWidget);
    expect(
      tester
          .widget<DropdownButtonFormField<int>>(
            find.byKey(const ValueKey('home-hole-count-selector')),
          )
          .initialValue,
      9,
    );
    await tester.tap(find.byKey(const ValueKey('home-hole-count-selector')));
    await tester.pumpAndSettle();
    expect(find.text('9 Holes'), findsWidgets);
    expect(find.text('18 Holes'), findsNothing);
    await tester.tap(find.text('9 Holes').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Total score'), '45');
    await tester.pumpAndSettle();

    final ninePar = seed.tees.first.holes.take(9).fold(0, (s, h) => s + h.par);
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Total score'))
          .decoration!
          .hintText,
      '$ninePar',
    );
    final btn = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Post Round'),
    );
    expect(btn.onPressed, isNotNull);
    expect(store.rounds, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, 'Post Round'));
    await tester.pumpAndSettle();
    expect(store.rounds.single.holes, hasLength(9));
  });

  testWidgets('quick post on Home adds a typed 18-hole round to the store', (
    tester,
  ) async {
    final store = GolfStore();
    await pumpTallHome(tester, store);

    expect(find.text('Quick score'), findsOneWidget);
    expect(find.text('18 Holes'), findsOneWidget);
    // The nine selector is hidden until 9 holes is picked.
    expect(find.text('Front 9'), findsNothing);

    await tester.enterText(find.widgetWithText(TextField, 'Total score'), '75');
    await tester.pumpAndSettle();
    // No summary line, no suffix echo, no helper, no Clear button.
    expect(find.textContaining('Total 75'), findsNothing);
    expect(find.text('Clear'), findsNothing);
    final field = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Total score'),
    );
    expect(field.decoration!.suffixText, isNull);
    expect(field.decoration!.helperText, isNull);

    expect(store.rounds, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, 'Post Round'));
    await tester.pumpAndSettle();

    expect(store.rounds, hasLength(1));
    final r = store.rounds.single;
    expect(r.holes, hasLength(18));
    expect(r.totalGross, 75);
    expect(r.startHole, 0);
    expect(r.handicapIndexAtPlay, isNull);
    expect(r.courseHandicap, isNull);
    expect(r.differential(store.teeById(r.courseId, r.teeId)!), isNotNull);
    expect(r.format, 'stroke');
    // The round is linked to the tee shown in the dropdown.
    expect(store.teeById(r.courseId, r.teeId), isNotNull);
    // The box clears so the next round is not typed over the last one.
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Total score'))
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets('quick post offers Save Scorecard next to the total', (
    tester,
  ) async {
    final store = GolfStore();
    await pumpTallHome(tester, store);

    // The button sits beside the Total score field, and both halves are
    // the same width.
    final photo = find.byKey(const ValueKey('quick-score-photo'));
    expect(photo, findsOneWidget);
    expect(find.text('Save Scorecard'), findsOneWidget);
    final field = find.widgetWithText(TextField, 'Total score');
    expect(
      (tester.getCenter(photo).dy - tester.getCenter(field).dy).abs(),
      lessThan(40),
    );
    expect(
      (tester.getSize(photo).width - tester.getSize(field).width).abs(),
      lessThan(16),
    );

    // The actual pick needs a camera or gallery, which tests do not have;
    // the sheet opening with both sources is what is asserted here.
    await tester.tap(photo);
    await tester.pumpAndSettle();
    expect(find.text('Take photo'), findsOneWidget);
    expect(find.text('Choose from gallery'), findsOneWidget);
    expect(find.text('Remove photo'), findsNothing);
  });

  testWidgets('quick score shows the latest score for the selected course', (
    tester,
  ) async {
    final store = GolfStore();
    final crystalLake = store.courseById('crystal-lake')!;
    final white = crystalLake.tees.firstWhere((tee) => tee.name == 'White');
    final otherTee = Tee(
      id: 'other-course-white',
      name: white.name,
      rating: white.rating,
      slope: white.slope,
      holes: white.holes,
    );
    final otherCourse = Course(
      id: 'other-course',
      name: 'Other Course',
      city: '',
      state: '',
      custom: true,
      tees: [otherTee],
    );
    store.courses = [...store.courses, otherCourse];
    store.rounds = [
      Round(
        id: 'crystal-old',
        courseId: crystalLake.id,
        teeId: white.id,
        playedAt: DateTime(2026, 1, 1),
        holes: [for (var i = 0; i < 9; i++) HoleScore(score: 5)],
      ),
      Round(
        id: 'crystal-last',
        courseId: crystalLake.id,
        teeId: white.id,
        playedAt: DateTime(2026, 1, 2),
        holes: [for (var i = 0; i < 9; i++) HoleScore(score: 4)],
      ),
      Round(
        id: 'other-last',
        courseId: otherCourse.id,
        teeId: otherTee.id,
        playedAt: DateTime(2026, 1, 3),
        holes: [for (var i = 0; i < 18; i++) HoleScore(score: 5)],
      ),
    ];
    await pumpTallHome(tester, store);

    expect(
      find.text('Last score at this course: 90 • 18 holes • White'),
      findsOneWidget,
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crystal Lake Golf Club').last);
    await tester.pumpAndSettle();
    expect(
      find.text('Last score at this course: 36 • 9 holes • White'),
      findsOneWidget,
    );
  });

  testWidgets('Home hole count selector only offers 9 and 18 holes', (
    tester,
  ) async {
    final store = GolfStore();
    await pumpTallHome(tester, store);

    await chooseHoleCount(
      tester,
      selectorKey: 'home-hole-count-selector',
      count: 9,
    );
    expect(find.textContaining('White • Front 9 33.8/125'), findsOneWidget);
    expect(find.textContaining('Back 9 34.5/123'), findsNothing);
    await tester.tap(find.text('Back 9'));
    await tester.pumpAndSettle();
    expect(find.textContaining('White • Back 9 34.5/123'), findsOneWidget);
    expect(find.textContaining('Front 9 33.8/125'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('home-hole-count-selector')));
    await tester.pumpAndSettle();
    expect(find.text('9 Holes'), findsWidgets);
    expect(find.text('18 Holes'), findsWidgets);
    expect(find.text('10 Holes'), findsNothing);
    expect(find.text('17 Holes'), findsNothing);
  });

  testWidgets('quick post caps holes at par plus five while establishing', (
    tester,
  ) async {
    final store = GolfStore();
    await pumpTallHome(tester, store);
    await chooseHoleCount(
      tester,
      selectorKey: 'home-hole-count-selector',
      count: 9,
    );

    await tester.enterText(find.widgetWithText(TextField, 'Total score'), '90');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Post Round'));
    await tester.pumpAndSettle();

    final r = store.rounds.single;
    final tee = store.teeById(r.courseId, r.teeId)!;
    for (var i = 0; i < r.holes.length; i++) {
      expect(
        r.holes[i].score,
        lessThanOrEqualTo(tee.holes[r.startHole + i].par + 5),
      );
    }
    expect(r.totalGross, lessThan(90));
    expect(find.textContaining('capped at max'), findsOneWidget);
  });

  testWidgets('picking 9 holes reveals front/back, and back 9 changes par', (
    tester,
  ) async {
    final store = GolfStore();
    final baseCourse = store.courses.first;
    final baseTee = baseCourse.defaultTee;
    final tee = Tee(
      id: 'split-rated-tee',
      name: 'White',
      rating: baseTee.rating,
      slope: baseTee.slope,
      frontNineRating: 33.8,
      frontNineSlope: 119,
      backNineRating: 34.5,
      backNineSlope: 124,
      holes: baseTee.holes,
    );
    store.courses = [
      Course(
        id: baseCourse.id,
        name: baseCourse.name,
        city: baseCourse.city,
        state: baseCourse.state,
        tees: [tee],
      ),
    ];
    await pumpTallHome(tester, store);

    await chooseHoleCount(
      tester,
      selectorKey: 'home-hole-count-selector',
      count: 9,
    );
    expect(find.text('Front 9'), findsOneWidget);
    expect(find.text('Back 9'), findsOneWidget);
    expect(find.textContaining('White • Front 9 33.8/119'), findsOneWidget);
    expect(find.textContaining('Back 9 34.5/124'), findsNothing);

    final field = find.widgetWithText(TextField, 'Total score');
    await tester.enterText(field, '36');
    await tester.pumpAndSettle();

    // The Total field's placeholder is the only place the chosen nine shows
    // up in the par. Front 9 is par 35 and back 9 is par 36 on the seed tee,
    // so a widget that ignored the front/back pick would report the same par
    // either way.
    String parHint() => tester
        .widget<TextField>(find.widgetWithText(TextField, 'Total score'))
        .decoration!
        .hintText!;

    expect(tee.parTotalFrom(0, 9), isNot(tee.parTotalFrom(9, 9)));
    expect(parHint(), '${tee.parTotalFrom(0, 9)}');

    await tester.tap(find.text('Back 9'));
    await tester.pumpAndSettle();
    expect(find.textContaining('White • Back 9 34.5/124'), findsOneWidget);
    expect(find.textContaining('Front 9 33.8/119'), findsNothing);
    // Switching nine clears the box, because the scores typed so far were
    // entered against the other nine's pars. Retype them to read the new par.
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    await tester.enterText(field, '36');
    await tester.pumpAndSettle();
    expect(parHint(), '${tee.parTotalFrom(9, 9)}');

    await tester.tap(find.widgetWithText(FilledButton, 'Post Round'));
    await tester.pumpAndSettle();

    final r = store.rounds.single;
    expect(r.holes, hasLength(9));
    expect(r.startHole, 9);
    expect(r.isBackNine, isTrue);
  });
  testWidgets('quick post refuses an impossible total and saves nothing', (
    tester,
  ) async {
    final store = GolfStore();
    await pumpTallHome(tester, store);

    // 10 strokes over 18 holes cannot be laid out as legal hole scores.
    await tester.enterText(find.widgetWithText(TextField, 'Total score'), '10');
    await tester.pumpAndSettle();

    // The button is disabled rather than saving a round nobody played.
    final btn = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Post Round'),
    );
    expect(btn.onPressed, isNull);
    expect(
      find.text('A total of 10 is not a score for 18 holes'),
      findsOneWidget,
    );
    expect(store.rounds, isEmpty);
  });

  testWidgets('quick post rejects a total that is not a number', (
    tester,
  ) async {
    final store = GolfStore();
    await pumpTallHome(tester, store);

    await tester.enterText(
      find.widgetWithText(TextField, 'Total score'),
      '75.5',
    );
    await tester.pumpAndSettle();

    expect(find.text('"75.5" is not a number'), findsOneWidget);
    expect(store.rounds, isEmpty);
  });

  testWidgets('quick post is offered on the Play page too, with front/back', (
    tester,
  ) async {
    final store = GolfStore();
    await pumpTallHome(tester, store);
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();

    // The Play page is the detailed path, but it must offer the same nine
    // choice, or a back nine could be recorded from Home but not here.
    expect(find.text('Front 9'), findsNothing);
    await chooseHoleCount(
      tester,
      selectorKey: 'play-hole-count-selector',
      count: 9,
    );
    expect(find.text('Front 9'), findsOneWidget);
    expect(find.text('Back 9'), findsOneWidget);

    // Par for hole 1 is read from the chosen nine: the editor's header is
    // "Hole 1 • Par N". Hole 1 of the back nine is the tee's hole 10, so the
    // header must follow the pick.
    final tee = store.courses.first.tees.first;
    expect(tee.holes[0].par, isNot(tee.holes[9].par));
    expect(find.text('Hole 1 • Par ${tee.holes[0].par}'), findsOneWidget);

    await tester.tap(find.text('Back 9'));
    await tester.pumpAndSettle();
    expect(find.text('Hole 1 • Par ${tee.holes[9].par}'), findsOneWidget);
    expect(find.text('Hole 1 • Par ${tee.holes[0].par}'), findsNothing);
  });
}

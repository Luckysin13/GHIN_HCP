import 'dart:io';
import 'dart:ui' show Canvas, Offset, Paint, PointMode, Size;

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
    final scoringOptions = find.ancestor(
      of: find.text('Eagle'),
      matching: find.byType(Wrap),
    );
    expect(
      tester.widget<Wrap>(scoringOptions.first).alignment,
      WrapAlignment.spaceBetween,
    );
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
    final birdie = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Birdie'),
    );
    final birdieColor = Color(store.scoreColorValue(-1));
    expect(birdie.backgroundColor, birdieColor.withValues(alpha: 0.18));
    expect(birdie.side?.color, birdieColor.withValues(alpha: 0.9));
    expect(
      (birdie.label as Text).style?.color,
      AppTheme.light.colorScheme.onSurface,
    );
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Par'))
          .selected,
      isTrue,
    );
    Container holeCell(String hole) {
      final label = find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.data == hole &&
            widget.style?.fontSize == 11,
      );
      final cell = find.ancestor(of: label, matching: find.byType(Container));
      expect(tester.getSize(cell.first).width, 46);
      return tester.widget<Container>(cell.first);
    }

    expect(
      (holeCell('1').decoration as BoxDecoration).color,
      const Color(0xFF607D8B),
    );

    // Birdie the hole (auto-advances), then return to confirm the chip and
    // hole strip still show the recorded score.
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is ChoiceChip && (w.label as Text).data == 'Birdie',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hole 2 • Par 4'), findsOneWidget);
    expect(
      (holeCell('1').decoration as BoxDecoration).color,
      const Color(0xFF43A047),
    );
    // Back to hole 1 via its strip chip (number text renders at size 11).
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is Text && w.data == '1' && w.style?.fontSize == 11,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hole 1 • Par 4'), findsOneWidget);

    final birdieChip = tester.widget<ChoiceChip>(
      find.byWidgetPredicate(
        (w) => w is ChoiceChip && (w.label as Text).data == 'Birdie',
      ),
    );
    expect(birdieChip.selected, isTrue);
    expect(birdieChip.selectedColor, const Color(0xFF43A047));
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
    expect(find.text('9 Holes'), findsOneWidget);
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

  testWidgets('custom course name opens edit without a pencil or yours tag', (
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

    expect(find.text('Search courses'), findsOneWidget);
    expect(find.textContaining('yours'), findsNothing);
    expect(find.byTooltip('Edit course'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('course-name-custom-name-tap')));
    await tester.pumpAndSettle();
    expect(find.text('Edit course'), findsOneWidget);
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
    final save = find.widgetWithText(FilledButton, 'Save course');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(store.courses.any((course) => course.name == 'New Course'), isTrue);
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
    final tee = course.tees.first;
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: scorecardTable(course, tee))),
    );
    await tester.pumpAndSettle();
    expect(find.text('FRONT 9'), findsOneWidget);
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

    await tester.enterText(find.widgetWithText(TextField, 'Total score'), '45');
    await tester.pumpAndSettle();

    expect(find.textContaining('Par '), findsOneWidget);
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
    // The summary line reads "Total 75  •  Par 71  •  +4".
    expect(find.textContaining('Total 75'), findsOneWidget);

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

  testWidgets('quick post supports an eligible partial 18-hole round', (
    tester,
  ) async {
    final store = GolfStore();
    final course = store.courses.first;
    final tee = course.defaultTee;
    for (var i = 0; i < 3; i++) {
      store.rounds.add(
        Round(
          id: 'prior-$i',
          courseId: course.id,
          teeId: tee.id,
          playedAt: DateTime.now().subtract(Duration(days: 3 - i)),
          holes: [for (final hole in tee.holes) HoleScore(score: hole.par)],
          courseHandicap: 0,
          handicapIndexAtPlay: 0,
        ),
      );
    }
    await pumpTallHome(tester, store);

    await chooseHoleCount(
      tester,
      selectorKey: 'home-hole-count-selector',
      count: 10,
    );
    await tester.tap(
      find.text('I had a valid reason for not completing the round'),
    );
    await tester.pumpAndSettle();
    final total = tee.parTotalFrom(0, 10);
    await tester.enterText(
      find.widgetWithText(TextField, 'Total score'),
      '$total',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Post Round'));
    await tester.pumpAndSettle();

    final partial = store.rounds.last;
    expect(partial.holes, hasLength(10));
    final index = store.handicapIndexBefore(DateTime.now())!;
    expect(
      partial.courseHandicap,
      whs.courseHandicap(
        handicapIndex: index,
        slopeRating: tee.slope.toDouble(),
        courseRating: tee.rating,
        par: tee.par,
      ),
    );
    expect(partial.differential(tee), isNotNull);
  });

  testWidgets('picking 9 holes reveals front/back, and back 9 changes par', (
    tester,
  ) async {
    final store = GolfStore();
    await pumpTallHome(tester, store);

    await chooseHoleCount(
      tester,
      selectorKey: 'home-hole-count-selector',
      count: 9,
    );
    expect(find.text('Front 9'), findsOneWidget);
    expect(find.text('Back 9'), findsOneWidget);

    final field = find.widgetWithText(TextField, 'Total score');
    await tester.enterText(field, '36');
    await tester.pumpAndSettle();

    // The summary line reads "Total N  •  Par X  •  +/-Y", and it is the only
    // place the chosen nine shows up in the par. Front 9 is par 35 and back 9
    // is par 36 on the seed tee, so a widget that ignored the front/back pick
    // would report the same par either way.
    // The summary line is "Total N  •  Par X  •  +/-Y". Matched on 'Par' since
    // the input's own label is "Total score" and its helper line has no par
    // summary. Not matched on the bullet, which is double-spaced.
    String summary() => tester
        .widgetList<Text>(
          find.byWidgetPredicate(
            (w) =>
                w is Text &&
                w.data != null &&
                w.data!.startsWith('Total ') &&
                w.data!.contains('Par'),
          ),
        )
        .single
        .data!;

    final tee = store.courses.first.tees.first;
    expect(tee.parTotalFrom(0, 9), isNot(tee.parTotalFrom(9, 9)));
    expect(summary(), contains('Par ${tee.parTotalFrom(0, 9)}'));

    await tester.tap(find.text('Back 9'));
    await tester.pumpAndSettle();
    // Switching nine clears the box, because the scores typed so far were
    // entered against the other nine's pars. Retype them to read the new par.
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    await tester.enterText(field, '36');
    await tester.pumpAndSettle();
    expect(summary(), contains('Par ${tee.parTotalFrom(9, 9)}'));

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

  testWidgets('trend spark plots the most recent 20 rounds, unclosed', (
    tester,
  ) async {
    final store = GolfStore();
    // 25 rounds. The five oldest are on the black tee, so they differ from
    // the twenty newest white-tee rounds: a spark that still reached back to
    // the start of the record would be a different shape from one showing
    // only the recent window the handicap index averages.
    for (var i = 0; i < 25; i++) {
      store.addRound(
        Round(
          id: 'r$i',
          courseId: 'crystal-lake',
          teeId: i < 5 ? 'crystal-lake-black' : 'crystal-lake-white',
          playedAt: DateTime(2026, 1, 1).add(Duration(days: i)),
          holes: List.generate(18, (h) => HoleScore(score: 4, putts: 2)),
        ),
      );
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 100,
            height: 48,
            child: TrendSpark(rounds: store.rounds, store: store),
          ),
        ),
      ),
    );

    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(TrendSpark),
        matching: find.byType(CustomPaint),
      ),
    );
    final canvas = _RecordingCanvas();
    paint.painter!.paint(canvas, const Size(100, 48));

    expect(canvas.points, hasLength(1));
    expect(canvas.points.single.mode, PointMode.lines);
    // Twenty points, all level: the newest 20 are identical, so the recent
    // window is flat. The five black-tee rounds are not in it.
    expect(canvas.points.single.pts, hasLength(20));
    for (final p in canvas.points.single.pts) {
      expect(p.dy, closeTo(44, 0.001));
    }
  });
}

/// A [Canvas] that records the polyline it is asked to draw, so a test can
/// see the points and the mode instead of the picture.
class _RecordingCanvas implements Canvas {
  final points = <PointsCall>[];

  @override
  void drawPoints(PointMode mode, List<Offset> points, Paint paint) {
    this.points.add(PointsCall(mode, points));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class PointsCall {
  final PointMode mode;
  final List<Offset> pts;
  PointsCall(this.mode, this.pts);
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghin_golf/app_theme.dart';
import 'package:ghin_golf/design_tokens.dart';
import 'package:ghin_golf/handicap_card.dart';
import 'package:ghin_golf/models.dart';
import 'package:ghin_golf/recent_rounds_section.dart';

Widget wrap(Widget child) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  group('tokens', () {
    test('the spacing scale is a doubling-ish 4pt grid', () {
      // A token that drifts off the grid is the thing this file exists to stop.
      for (final v in [
        Insets.xs,
        Insets.sm,
        Insets.md,
        Insets.lg,
        Insets.xl,
        Insets.xxl,
        Insets.xxxl,
        Insets.huge,
        Insets.giant,
      ]) {
        expect(v % 4, 0, reason: '$v is off the 4pt grid');
      }
    });

    test('radii are ordered smallest control to largest surface', () {
      expect(Radii.control, lessThan(Radii.card));
      expect(Radii.card, lessThan(Radii.sheet));
      expect(Radii.sheet, lessThan(Radii.dialog));
    });
  });

  group('theme', () {
    test('the legacy build flag is off by default', () {
      expect(legacyUi, isFalse);
    });

    test('legacy and new themes are different', () {
      final legacy = ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      );
      expect(
        AppTheme.light.colorScheme.primary,
        isNot(legacy.colorScheme.primary),
        reason: 'the new look is seeded from the brand green, not Colors.green',
      );
    });

    test('the theme actually styles the components it claims to', () {
      final t = AppTheme.light;
      expect(t.cardTheme.elevation, 0);
      expect(t.filledButtonTheme.style?.minimumSize?.resolve({})?.height, 48);
      expect(t.snackBarTheme.behavior, SnackBarBehavior.floating);
      expect(t.navigationBarTheme.height, 76);
      expect(t.dialogTheme.elevation, 0);
    });

    test('light and dark are both usable', () {
      expect(AppTheme.light.brightness, Brightness.light);
      expect(AppTheme.dark.brightness, Brightness.dark);
      // Same seed both ways, so the brand does not change with the clock.
      expect(AppTheme.dark.colorScheme.primary, isNotNull);
    });

    test('light metadata inherits readable colors from the theme', () {
      final scheme = AppTheme.light.colorScheme;
      expect(AppType.meta.color, isNull);
      expect(
        _contrast(scheme.onSurfaceVariant, scheme.surface),
        greaterThan(4.5),
      );
      expect(
        _contrast(scheme.onSurfaceVariant, scheme.surfaceContainerLow),
        greaterThan(4.5),
      );
    });

    test('active() honours the legacy switch', () {
      expect(AppTheme.active(Brightness.light).brightness, Brightness.light);
    });
  });

  group('HandicapCard', () {
    testWidgets('shows the index when there is one', (tester) async {
      await tester.pumpWidget(wrap(HandicapCard(index: 11.2, roundCount: 8)));
      expect(find.text('11.2'), findsOneWidget);
      expect(
        tester.getSize(find.byType(HandicapCard)).height,
        lessThanOrEqualTo(140),
      );
    });

    testWidgets('a missing index is a real state, not a zero', (tester) async {
      await tester.pumpWidget(wrap(HandicapCard(index: null, roundCount: 0)));
      expect(find.text('— —'), findsOneWidget);
      expect(find.text('0.0'), findsNothing);
      expect(find.textContaining('Post a few rounds'), findsOneWidget);
    });

    testWidgets('a single round is not pluralised', (tester) async {
      await tester.pumpWidget(wrap(HandicapCard(index: 12, roundCount: 1)));
      expect(find.text('1 round'), findsOneWidget);
      expect(find.textContaining('rounds'), findsNothing);
    });

    testWidgets('no rounds reads as a start, not a failure', (tester) async {
      await tester.pumpWidget(wrap(HandicapCard(index: null, roundCount: 0)));
      expect(find.text('No rounds yet'), findsOneWidget);
    });

    testWidgets('pending uploads are surfaced', (tester) async {
      await tester.pumpWidget(
        wrap(HandicapCard(index: 10, roundCount: 4, pending: 2)),
      );
      expect(find.text('2 syncing'), findsOneWidget);
    });

    testWidgets('it lays out at a narrow width without overflowing', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        wrap(HandicapCard(index: 11.2, roundCount: 128, pending: 3)),
      );
      expect(tester.takeException(), isNull);
      final title = tester.getRect(find.text('HANDICAP INDEX'));
      final indexValue = tester.getRect(find.text('11.2'));
      expect(title.overlaps(indexValue), isFalse);
      expect(title.right, lessThanOrEqualTo(indexValue.left));
    });
  });

  group('RecentRoundsSection', () {
    Future<void> pump(WidgetTester tester, {int count = 2}) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecentRoundsSection(
                rows: [
                  for (var i = 0; i < count; i++)
                    FakeRound(i, 70 + i).row('Bent Creek (White)'),
                ],
                onEdit: (_) {},
                onDelete: (_) {},
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('the empty state is written, not just blank', (tester) async {
      await pump(tester, count: 0);
      expect(find.text('RECENT ROUNDS'), findsOneWidget);
      expect(find.text('No rounds yet'), findsOneWidget);
    });

    testWidgets('rows show the score, the course and the handicap', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('70'), findsOneWidget);
      expect(find.text('Bent Creek (White)'), findsNWidgets(2));
      expect(find.text('CH 12'), findsNWidgets(2));
    });

    testWidgets('the row is tappable for edit and has its own controls', (
      tester,
    ) async {
      var edited = 0, deleted = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecentRoundsSection(
                rows: [FakeRound(0, 70).row('Bent Creek')],
                onEdit: (_) => edited++,
                onDelete: (_) => deleted++,
              ),
            ),
          ),
        ),
      );
      expect(find.byTooltip('Edit round'), findsNothing);
      expect(find.byTooltip('Delete round'), findsOneWidget);

      await tester.tap(find.text('Bent Creek'));
      expect(edited, 1);
      await tester.tap(find.byTooltip('Delete round'));
      expect(edited, 1);
      expect(deleted, 1);
    });

    testWidgets('a custom limit keeps the list a summary', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecentRoundsSection(
                rows: [
                  for (var i = 0; i < 30; i++)
                    FakeRound(i, 70 + i).row('Bent Creek'),
                ],
                limit: 3,
                onEdit: (_) {},
                onDelete: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(find.byType(Dismissible), findsNWidgets(3));
    });

    testWidgets('shows 20 recent rounds and expands to all rounds', (
      tester,
    ) async {
      await pump(tester, count: 25);
      expect(find.byType(Dismissible), findsNWidgets(20));

      final toggle = find.byKey(const ValueKey('recent-rounds-toggle'));
      expect(find.text('Show all rounds'), findsOneWidget);
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();

      expect(find.byType(Dismissible), findsNWidgets(25));
      expect(find.text('Show fewer rounds'), findsOneWidget);

      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.byType(Dismissible), findsNWidgets(20));
      expect(find.text('Show all rounds'), findsOneWidget);
    });

    testWidgets('the date is MM-DD-YY', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecentRoundsSection(
                rows: [FakeRound(0, 70).row('Bent Creek')],
                onEdit: (_) {},
                onDelete: (_) {},
              ),
            ),
          ),
        ),
      );
      // 2026-09-20, American order, two-digit year.
      expect(find.textContaining('09-20-26'), findsOneWidget);
    });

    testWidgets('the row shows the par for the holes played', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecentRoundsSection(
                rows: [FakeRound(0, 70, par: 71).row('Bent Creek')],
                onEdit: (_) {},
                onDelete: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(find.textContaining('Par 71'), findsOneWidget);
    });

    testWidgets('under par reads as a negative number', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecentRoundsSection(
                rows: [FakeRound(0, 70, par: 72).row('Bent Creek')],
                onEdit: (_) {},
                onDelete: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('-2'), findsOneWidget);
    });

    testWidgets('level par reads as E, not a bare zero', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecentRoundsSection(
                rows: [FakeRound(0, 72, par: 72).row('Bent Creek')],
                onEdit: (_) {},
                onDelete: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('E'), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('over par carries an explicit plus', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecentRoundsSection(
                rows: [FakeRound(0, 77, par: 72).row('Bent Creek')],
                onEdit: (_) {},
                onDelete: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('+5'), findsOneWidget);
    });

    testWidgets('the row shows the tee rating to one decimal', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecentRoundsSection(
                rows: [FakeRound(0, 70, rating: 71.2437).row('Bent Creek')],
                onEdit: (_) {},
                onDelete: (_) {},
              ),
            ),
          ),
        ),
      );
      // Tee ratings are published to one decimal; printing 71.2437 would
      // imply precision the source does not have.
      expect(find.text('Par 72 • Rating 71.2 • Slope 124'), findsOneWidget);
      expect(find.text('09-20-26'), findsOneWidget);
    });

    testWidgets('the row shows the slope', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecentRoundsSection(
                rows: [FakeRound(0, 70, slope: 131).row('Bent Creek')],
                onEdit: (_) {},
                onDelete: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(find.textContaining('Slope 131'), findsOneWidget);
    });

    testWidgets('rating and slope are readable with the date and par', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecentRoundsSection(
                rows: [FakeRound(0, 70, par: 71).row('Bent Creek')],
                onEdit: (_) {},
                onDelete: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('Par 71 • Rating 71.2 • Slope 124'), findsOneWidget);
      expect(find.text('09-20-26'), findsOneWidget);
    });

    testWidgets('a deleted tee shows dashes rather than zeroes', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecentRoundsSection(
                rows: [
                  FakeRound(0, 70, rating: null, slope: null).row('Bent Creek'),
                ],
                onEdit: (_) {},
                onDelete: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(find.textContaining('Rating —'), findsOneWidget);
      expect(find.textContaining('Slope —'), findsOneWidget);
      expect(find.textContaining('Rating 0.0'), findsNothing);
    });

    testWidgets('tee facts do not overflow a phone', (tester) async {
      // The facts can wrap on a narrow screen but must never overflow.
      tester.view.physicalSize = const Size(320 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecentRoundsSection(
                rows: [
                  FakeRound(0, 70, rating: 71.2, slope: 124).row('Bent Creek'),
                ],
                onEdit: (_) {},
                onDelete: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the row shows the tee rating to one decimal', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecentRoundsSection(
                rows: [FakeRound(0, 70, rating: 71.2437).row('Bent Creek')],
                onEdit: (_) {},
                onDelete: (_) {},
              ),
            ),
          ),
        ),
      );
      // Tee ratings are published to one decimal; printing 71.2437 would
      // imply precision the source does not have.
      expect(find.text('Par 72 • Rating 71.2 • Slope 124'), findsOneWidget);
      expect(find.text('09-20-26'), findsOneWidget);
    });

    testWidgets('the row shows the slope', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecentRoundsSection(
                rows: [FakeRound(0, 70, slope: 131).row('Bent Creek')],
                onEdit: (_) {},
                onDelete: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(find.textContaining('Slope 131'), findsOneWidget);
    });

    testWidgets('rating and slope are readable with the date and par', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecentRoundsSection(
                rows: [FakeRound(0, 70, par: 71).row('Bent Creek')],
                onEdit: (_) {},
                onDelete: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('Par 71 • Rating 71.2 • Slope 124'), findsOneWidget);
      expect(find.text('09-20-26'), findsOneWidget);
    });

    testWidgets('a deleted tee shows dashes rather than zeroes', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecentRoundsSection(
                rows: [
                  FakeRound(0, 70, rating: null, slope: null).row('Bent Creek'),
                ],
                onEdit: (_) {},
                onDelete: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(find.textContaining('Rating —'), findsOneWidget);
      expect(find.textContaining('Slope —'), findsOneWidget);
      expect(find.textContaining('Rating 0.0'), findsNothing);
    });

    testWidgets('tee facts do not overflow a phone', (tester) async {
      // The facts can wrap on a narrow screen but must never overflow.
      tester.view.physicalSize = const Size(320 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecentRoundsSection(
                rows: [
                  FakeRound(0, 70, rating: 71.2, slope: 124).row('Bent Creek'),
                ],
                onEdit: (_) {},
                onDelete: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the meta line wraps on a phone and not on a tablet', (
      tester,
    ) async {
      Future<double> metaHeight(Size size) async {
        tester.view.physicalSize = Size(size.width * 3, size.height * 3);
        tester.view.devicePixelRatio = 3.0;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: SingleChildScrollView(
                child: RecentRoundsSection(
                  rows: [FakeRound(0, 70).row('Bent Creek')],
                  onEdit: (_) {},
                  onDelete: (_) {},
                ),
              ),
            ),
          ),
        );
        return tester
            .getSize(find.text('Par 72 • Rating 71.2 • Slope 124'))
            .height;
      }

      final phone = await metaHeight(const Size(320, 800));
      final tablet = await metaHeight(const Size(1056, 800));
      addTearDown(tester.view.reset);

      // Tee facts do not fit across a phone, so the line wraps onto a second
      // row. Clipping the slope off the end is worse than a taller row.
      expect(phone, greaterThan(tablet));
    });

    testWidgets('the to-par figure does not reflow between signs', (
      tester,
    ) async {
      // "-1" and "+1" are the same width, but a signed value and an unsigned
      // one are not, and a row that reshuffles when you scroll it is unreadable.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecentRoundsSection(
                rows: [
                  FakeRound(0, 71, par: 72).row('Under'),
                  FakeRound(1, 73, par: 72).row('Over'),
                ],
                onEdit: (_) {},
                onDelete: (_) {},
              ),
            ),
          ),
        ),
      );
      final under = tester.getSize(find.text('-1'));
      final over = tester.getSize(find.text('+1'));
      expect(under.width, over.width);
    });

    testWidgets('rows do not overflow at a narrow width', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecentRoundsSection(
                rows: [
                  FakeRound(0, 70).row(
                    'Crystal Lake Golf Club at the very long name resort (White)',
                  ),
                ],
                onEdit: (_) {},
                onDelete: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        tester
            .widget<Text>(
              find.text(
                'Crystal Lake Golf Club at the very long name resort (White)',
              ),
            )
            .maxLines,
        isNull,
        reason: 'course names should wrap rather than be truncated',
      );
    });
  });
}

double _contrast(Color foreground, Color background) {
  final lighter = foreground.computeLuminance() > background.computeLuminance()
      ? foreground.computeLuminance()
      : background.computeLuminance();
  final darker = foreground.computeLuminance() < background.computeLuminance()
      ? foreground.computeLuminance()
      : background.computeLuminance();
  return (lighter + 0.05) / (darker + 0.05);
}

/// Minimal stand-in so the section can be exercised without a full store.
class FakeRound {
  FakeRound(
    this.i,
    this.gross, {
    this.par = 72,
    this.holes = 18,
    this.rating = 71.2,
    this.slope = 124,
  });
  final int i;
  final int gross;
  final int par;
  final int holes;
  final double? rating;
  final int? slope;

  RecentRound row(String courseName) => RecentRound(
    round: build(),
    courseName: courseName,
    par: par,
    rating: rating,
    slope: slope,
  );

  Round build() {
    // 18 holes that sum to exactly [gross], so the row under test shows the
    // number the test asserts on.
    final base = gross ~/ 18, extra = gross % 18;
    return Round(
      id: 'r$i',
      courseId: 'c1',
      teeId: 'tee-White',
      // Local, not UTC: the row renders in local time, and a UTC midnight
      // would read as the previous day anywhere west of Greenwich.
      playedAt: DateTime(2026, 9, 20).add(Duration(days: i)),
      courseHandicap: 12,
      holes: [
        for (var h = 0; h < holes; h++)
          HoleScore(score: base + (h < extra ? 1 : 0)),
      ],
    );
  }
}

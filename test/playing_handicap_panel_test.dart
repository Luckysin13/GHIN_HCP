import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ghin_golf/playing_handicap_panel.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  Future<void> expand(WidgetTester tester) async {
    await tester.tap(find.text('Playing Handicap'));
    await tester.pumpAndSettle();
  }

  testWidgets('the header stays up but the rows wait for the arrow', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const PlayingHandicapPanel(
      unroundedCourseHandicap: 13.0,
    )));

    // Title and the Course Handicap footnote are always visible.
    expect(find.text('Playing Handicap'), findsOneWidget);
    expect(find.textContaining('Course Handicap 13.0'), findsOneWidget);
    expect(find.textContaining('allowances per WHS Rule 6.2'), findsOneWidget);

    // The format rows are tucked away until the arrow is pressed.
    expect(find.text('Stroke Play'), findsNothing);

    await expand(tester);
    expect(find.text('Stroke Play'), findsOneWidget);
    expect(find.byType(ExpansionTile), findsOneWidget);
  });

  testWidgets('every format and allowance row is present', (tester) async {
    await tester.pumpWidget(wrap(const PlayingHandicapPanel(
      unroundedCourseHandicap: 13.0,
    )));
    await expand(tester);

    for (final label in [
      'Stroke Play',
      'Match Play',
      'Best Ball (stroke)',
      'Best Ball (match)',
      'Alternate Shot (stroke)',
      'Alternate Shot (match)',
      'Best Ball',
      'Best 2 Ball',
      'Best 3 Ball',
      'Best 4 Ball',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('95%'), findsWidgets);
    expect(find.text('90%'), findsWidgets);
    expect(find.text('50% of combined CH'), findsWidgets);
    expect(find.text('50% of CH difference'), findsWidgets);
    expect(find.textContaining('Course Handicap 13.0'), findsOneWidget);
  });

  testWidgets('single-player rows apply the allowance to the unrounded CH', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const PlayingHandicapPanel(
      unroundedCourseHandicap: 13.0,
    )));
    await expand(tester);

    String ph(String rowKey) => tester
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(ValueKey(rowKey)),
            matching: find.byType(Text),
          ),
        )
        .last.data!;

    // 13.0 × 0.95 = 12.35 -> 12.
    expect(ph('ph-medal'), '12');
    // 13.0 × 1.00 = 13.
    expect(ph('ph-individualMatch'), '13');
    // 13.0 × 0.85 = 11.05 -> 11.
    expect(ph('ph-fourBallStroke'), '11');
    // 13.0 × 0.90 = 11.7 -> 12.
    expect(ph('ph-fourBallMatch'), '12');
    expect(ph('ph-best1Of4'), '10');
    expect(ph('ph-best2Of4'), '11');
    expect(ph('ph-best3Of4'), '13');
    expect(ph('ph-best4Of4'), '13');
  });

  testWidgets('alternate shot rows defer to the combined Course Handicaps', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const PlayingHandicapPanel(
      unroundedCourseHandicap: 13.0,
    )));
    await expand(tester);

    String value(String rowKey) => tester
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(ValueKey(rowKey)),
            matching: find.byType(Text),
          ),
        )
        .last.data!;
    expect(value('ph-foursomesStroke'), '—');
    expect(value('ph-foursomesMatch'), '—');
  });

  testWidgets('with no Course Handicap the panel says a score is needed', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const PlayingHandicapPanel(
      unroundedCourseHandicap: null,
    )));
    // Footnote still visible, the prompt is behind the arrow.
    expect(find.textContaining('Course Handicap —'), findsOneWidget);
    expect(find.text('Post three scores (54 holes) to see your Playing Handicap.'), findsNothing);

    await expand(tester);
    expect(
      find.text('Post three scores (54 holes) to see your Playing Handicap.'),
      findsOneWidget,
    );
    expect(find.text('13'), findsNothing);
  });
}
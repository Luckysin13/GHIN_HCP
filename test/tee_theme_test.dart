import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghin_golf/main.dart';
import 'package:ghin_golf/models.dart';

/// The scorecard header is the one place a tee box's color is shown, so this
/// pins that a tee named after a real color is not painted as some other
/// color. Purple and Orange used to fall through to a teal default and render
/// green, which made a Purple box indistinguishable from a Green one.
void main() {
  Course courseWith(String teeName) => Course(
    id: 'c',
    name: 'C',
    city: '',
    state: '',
    tees: [],
  );

  Tee tee(String name) => Tee(
    id: name,
    name: name,
    rating: 70,
    slope: 120,
    holes: [
      for (var i = 0; i < 18; i++)
        HoleInfo(number: i + 1, par: 4, yardage: 400, strokeIndex: i + 1),
    ],
  );

  /// The header's background color, read off the first painted container.
  Future<int?> headerColor(WidgetTester tester, String name) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: scorecardTable(courseWith(name), tee(name))),
        ),
      ),
    );
    final colors =
        tester
            .widgetList<Container>(find.byType(Container))
            .map((c) => c.decoration)
            .whereType<BoxDecoration>()
            .map((d) => d.color)
            .where((c) => c != null)
            .toList();
    expect(colors, isNotEmpty, reason: 'no header color found for $name');
    return colors.first!.toARGB32();
  }

  testWidgets('each color name gets its own color', (tester) async {
    // The eight the app always supported, unchanged.
    expect(await headerColor(tester, 'Black'), 0xFF212121);
    expect(await headerColor(tester, 'Blue'), 0xFF1565C0);
    expect(await headerColor(tester, 'White'), 0xFFEEEEEE);
    expect(await headerColor(tester, 'Gold'), 0xFFF9A825);
    expect(await headerColor(tester, 'Yellow'), 0xFFF9A825);
    expect(await headerColor(tester, 'Red'), 0xFFC62828);
    expect(await headerColor(tester, 'Green'), 0xFF2E7D32);
    expect(await headerColor(tester, 'Silver'), 0xFF78909C);
    expect(await headerColor(tester, 'Gray'), 0xFF78909C);
  });

  testWidgets('Purple and Orange are not painted green', (tester) async {
    // The bug: these names were not in the switch and both took the teal
    // default, so a Purple box looked like a Green one.
    final green = await headerColor(tester, 'Green');
    expect(await headerColor(tester, 'Purple'), isNot(green));
    expect(await headerColor(tester, 'Orange'), isNot(green));
  });

  testWidgets('every mapped name renders a distinct color', (tester) async {
    final names = [
      'Black', 'Blue', 'White', 'Gold', 'Yellow', 'Red', 'Green',
      'Purple', 'Orange', 'Bronze', 'Silver', 'Gray', 'Grey',
    ];
    final seen = <String, int>{};
    for (final n in names) {
      final c = await headerColor(tester, n);
      // Gold/Yellow and Silver/Gray/Grey are deliberate pairs; everything
      // else must stand on its own.
      if (const {'Gold': 'Yellow', 'Silver': 'Gray', 'Gray': 'Grey'}
          .entries
          .any((e) => e.value == n)) {
        continue;
      }
      for (final e in seen.entries) {
        expect(
          c,
          isNot(seen[e.key]),
          reason: '$n and ${e.key} render the same color',
        );
      }
      seen[n] = c!;
    }
  });

  testWidgets('an unknown tee name is neutral, not a real color', (tester) async {
    // Neutral rather than teal: a name the app does not know should look
    // uncoloured instead of quietly resembling a green tee box.
    final unknown = await headerColor(tester, 'Combo');
    expect(unknown, 0xFF455A64);
    expect(unknown, isNot(await headerColor(tester, 'Green')));
    expect(unknown, isNot(await headerColor(tester, 'Purple')));
  });

  testWidgets('name matching ignores case and stray spaces', (tester) async {
    expect(await headerColor(tester, '  pUrPlE '), await headerColor(tester, 'Purple'));
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghin_golf/export.dart';
import 'package:ghin_golf/main.dart';
import 'package:ghin_golf/store.dart';
import 'package:ghin_golf/theme_toggle.dart';

/// The brightness the widget tree actually resolved to, which is the only
/// thing a user can see.
Brightness resolvedBrightness(WidgetTester tester) {
  final ctx = tester.element(find.byType(ThemeModeButton));
  return Theme.of(ctx).brightness;
}

void main() {
  group('store theme preference', () {
    test('starts out following the system', () {
      expect(GolfStore().themeMode, ThemeMode.system);
    });

    test('is only writable through setThemeMode', () {
      final store = GolfStore();
      var notified = 0;
      store.addListener(() => notified++);
      store.setThemeMode(ThemeMode.dark);
      expect(store.themeMode, ThemeMode.dark);
      expect(notified, 1);
    });

    test('setting the mode it already has does not repaint', () {
      final store = GolfStore()..setThemeMode(ThemeMode.dark);
      var notified = 0;
      store.addListener(() => notified++);
      store.setThemeMode(ThemeMode.dark);
      expect(notified, 0);
    });

    test('survives a save and load', () async {
      final dir = await Directory.systemTemp.createTemp('ghin-theme');
      addTearDown(() => dir.delete(recursive: true));
      final file = '${dir.path}/save.json';
      GolfStore.testFilePath = file;
      addTearDown(() => GolfStore.testFilePath = null);

      final store = GolfStore()..setThemeMode(ThemeMode.dark);
      await store.save();

      final reloaded = GolfStore();
      await reloaded.load();
      expect(reloaded.themeMode, ThemeMode.dark);
    });

    test('an unknown mode in the save file falls back to the system', () async {
      final dir = await Directory.systemTemp.createTemp('ghin-theme');
      addTearDown(() => dir.delete(recursive: true));
      final file = '${dir.path}/save.json';
      GolfStore.testFilePath = file;
      addTearDown(() => GolfStore.testFilePath = null);
      File(file).writeAsStringSync(json.encode({'themeMode': 'ultraviolet'}));

      final store = GolfStore();
      await store.load();
      // A file from a newer build must not stop the app opening.
      expect(store.themeMode, ThemeMode.system);
    });

    test('a save file with no theme key loads as system', () async {
      final dir = await Directory.systemTemp.createTemp('ghin-theme');
      addTearDown(() => dir.delete(recursive: true));
      final file = '${dir.path}/save.json';
      GolfStore.testFilePath = file;
      addTearDown(() => GolfStore.testFilePath = null);
      File(file).writeAsStringSync(json.encode({'rounds': []}));

      final store = GolfStore();
      await store.load();
      expect(store.themeMode, ThemeMode.system);
    });
  });

  group('theme toggle', () {
    Future<GolfStore> pumpHome(WidgetTester tester) async {
      final store = GolfStore();
      await tester.pumpWidget(GhinApp(store: store));
      await tester.pumpAndSettle();
      return store;
    }

    Future<void> choose(WidgetTester tester, String label) async {
      await tester.tap(find.byTooltip('Appearance'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    testWidgets('offers all three modes by name', (tester) async {
      await pumpHome(tester);
      await tester.tap(find.byTooltip('Appearance'));
      await tester.pumpAndSettle();
      expect(find.text('Match system'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
    });

    testWidgets('picking Dark actually darkens the app', (tester) async {
      final store = await pumpHome(tester);
      expect(resolvedBrightness(tester), Brightness.light);

      await choose(tester, 'Dark');
      expect(store.themeMode, ThemeMode.dark);
      expect(resolvedBrightness(tester), Brightness.dark);
    });

    testWidgets('picking Light actually lightens the app', (tester) async {
      final store = await pumpHome(tester);
      await choose(tester, 'Dark');
      await choose(tester, 'Light');
      expect(store.themeMode, ThemeMode.light);
      expect(resolvedBrightness(tester), Brightness.light);
    });

    testWidgets('the check marks the mode in force', (tester) async {
      await pumpHome(tester);
      await choose(tester, 'Dark');

      await tester.tap(find.byTooltip('Appearance'));
      await tester.pumpAndSettle();
      // Scoped to the menu rows: the rest of Home has check marks of its own,
      // so a global count would be asserting about the wrong widgets.
      Finder row(String label) => find.ancestor(
        of: find.text(label),
        matching: find.byType(PopupMenuItem<ThemeMode>),
      );

      expect(
        find.descendant(of: row('Dark'), matching: find.byIcon(Icons.check)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row('Light'), matching: find.byIcon(Icons.check)),
        findsNothing,
      );
      expect(
        find.descendant(
          of: row('Match system'),
          matching: find.byIcon(Icons.check),
        ),
        findsNothing,
      );
    });

    testWidgets('the icon follows the mode in force', (tester) async {
      await pumpHome(tester);
      expect(find.byIcon(Icons.brightness_auto_outlined), findsOneWidget);

      await choose(tester, 'Dark');
      expect(find.byIcon(Icons.dark_mode_outlined), findsOneWidget);
      expect(find.byIcon(Icons.brightness_auto_outlined), findsNothing);

      await choose(tester, 'Light');
      expect(find.byIcon(Icons.light_mode_outlined), findsOneWidget);
    });

    testWidgets('system follows the platform brightness', (tester) async {
      await pumpHome(tester);
      // The test platform reports light; choosing System must land on light
      // even though Dark was selected a moment ago.
      await choose(tester, 'Dark');
      await choose(tester, 'Match system');
      expect(resolvedBrightness(tester), Brightness.light);
    });

    test('choosing a mode writes it to the save file', () async {
      final dir = await Directory.systemTemp.createTemp('ghin-theme-write');
      addTearDown(() => dir.delete(recursive: true));
      GolfStore.testFilePath = '${dir.path}/save.json';
      addTearDown(() => GolfStore.testFilePath = null);

      final store = GolfStore()..setThemeMode(ThemeMode.dark);
      await store.save();

      final written =
          json.decode(File(GolfStore.testFilePath!).readAsStringSync())
              as Map<String, dynamic>;
      expect(written['themeMode'], 'dark');
    });
  });

  group('theme in a full backup', () {
    test('a backup carries the appearance setting', () async {
      final dir = await Directory.systemTemp.createTemp('ghin-theme-bak');
      addTearDown(() => dir.delete(recursive: true));
      GolfStore.testFilePath = '${dir.path}/save.json';
      addTearDown(() => GolfStore.testFilePath = null);

      final store = GolfStore()..setThemeMode(ThemeMode.dark);
      await store.save();
      final b = parseBackup(store.exportRoundsJson());
      expect(b.themeMode, 'dark');
    });

    test('a backup with only a new appearance is not "nothing new"', () {
      final store = GolfStore()..setThemeMode(ThemeMode.light);
      final b = Backup(rounds: const [], courses: const [], themeMode: 'dark');
      expect(store.previewBackup(b).themeChanged, isTrue);
    });

    test('a backup whose appearance matches is not a change', () {
      final store = GolfStore()..setThemeMode(ThemeMode.dark);
      final b = Backup(rounds: const [], courses: const [], themeMode: 'dark');
      expect(store.previewBackup(b).themeChanged, isFalse);
    });

    test('a backup from before the setting existed changes nothing', () {
      final store = GolfStore()..setThemeMode(ThemeMode.dark);
      final b = Backup(rounds: const [], courses: const []);
      expect(store.previewBackup(b).themeChanged, isFalse);
    });

    test('restoring the backup changes the appearance', () async {
      final store = GolfStore()..setThemeMode(ThemeMode.light);
      final b = Backup(rounds: const [], courses: const [], themeMode: 'dark');
      // Awaited: the appearance is applied after the photo restore, so a
      // synchronous call would check it before it has been set.
      await store.importBackup(b);
      expect(store.themeMode, ThemeMode.dark);
    });
  });
}

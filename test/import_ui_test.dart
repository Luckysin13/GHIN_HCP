import 'dart:convert';
import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghin_golf/export.dart';
import 'package:ghin_golf/main.dart';
import 'package:ghin_golf/models.dart';
import 'package:ghin_golf/store.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

const _docsChannel = MethodChannel('plugins.flutter.io/path_provider');

/// Stands in for the platform's documents directory.
class _FakeDocs {
  final root = Directory.systemTemp.createTempSync('ghin_import_ui_test');
}

/// Hands [pickBackupFile] a real temp file, so the import path is exercised
/// end to end rather than stubbed out.
class _FakeFileSelector extends FileSelectorPlatform
    with MockPlatformInterfaceMixin {
  _FakeFileSelector(this.path);

  final String? path;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    final p = path;
    return p == null ? null : XFile(p);
  }
}

Course _course({String id = 'c1', String name = 'Bent Creek'}) => Course(
  id: id,
  name: name,
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
  custom: true,
);

Round _round({String id = 'r1'}) => Round(
  id: id,
  courseId: 'c1',
  teeId: 'tee-White',
  playedAt: DateTime.utc(2026, 9, 20),
  holes: [for (var i = 0; i < 18; i++) HoleScore(score: 4, putts: 2)],
);

void main() {
  late _FakeDocs docs;
  late GolfStore store;

  setUp(() {
    docs = _FakeDocs();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_docsChannel, (call) async {
          if (call.method == 'getApplicationDocumentsPath') {
            return docs.root.path;
          }
          return null;
        });
    store = GolfStore()..rounds = [_round()];
    store.courses = [_course()];
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_docsChannel, null);
    docs.root.deleteSync(recursive: true);
  });

  /// Writes [contents] as a backup file and points the picker at it.
  void serve(String contents) {
    final f = File('${docs.root.path}/incoming.json')
      ..writeAsStringSync(contents);
    FileSelectorPlatform.instance = _FakeFileSelector(f.path);
  }

  void serveNothing() {
    FileSelectorPlatform.instance = _FakeFileSelector(null);
  }

  Future<void> openMenuAndImport(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: HomePage(store: store)));
    await tester.tap(find.byTooltip('Backup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import backup'));
    // The picker is an awaited platform call, so frames alone will not settle.
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
  }

  testWidgets(
    'a backup whose rounds are all present still restores its courses',
    (tester) async {
      // The reported bug: the restore asked only about rounds, said "nothing
      // new", and never imported the courses the file also carried.
      store.courses = [];
      serve(
        toJson(
          [_round()], // already in the app
          [_course(name: 'Restored Course')],
        ),
      );

      await openMenuAndImport(tester);
      expect(find.text('Restore backup?'), findsOneWidget);
      expect(find.textContaining('1 course'), findsOneWidget);

      await tester.tap(find.text('Restore'));
      await tester.pumpAndSettle();
      expect(store.courses.map((c) => c.name), contains('Restored Course'));
    },
  );

  testWidgets('a settings-only backup still opens the restore dialog', (
    tester,
  ) async {
    serve(toJson([], [], scoreColors: {2: 0xFF00FF00}));

    await openMenuAndImport(tester);
    expect(find.text('Restore backup?'), findsOneWidget);
    expect(find.textContaining('score color'), findsOneWidget);

    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(store.scoreColorValue(2), 0xFF00FF00);
  });

  testWidgets('a backup carrying only an appearance change still restores', (
    tester,
  ) async {
    // A backup with no rounds and no courses used to be reported as "nothing
    // new" and dropped, which silently discarded the brightness setting.
    store.setThemeMode(ThemeMode.light);
    serve(toJson([], [], themeMode: 'dark'));

    await openMenuAndImport(tester);
    expect(find.text('Restore backup?'), findsOneWidget);
    expect(find.text('Nothing new'), findsNothing);

    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(store.themeMode, ThemeMode.dark);
  });

  testWidgets('the dialog names every kind of thing it will bring in', (
    tester,
  ) async {
    store.courses = [];
    serve(
      toJson(
        [_round(), _round(id: 'r2')],
        [_course(name: 'New Course')],
        scoreColors: {1: 0xFF00FF00},
      ),
    );

    await openMenuAndImport(tester);
    expect(
      find.text(
        'Adds 1 round, 1 course, 1 score color. '
        'Rounds and courses you already have are left alone, '
        'and nothing is deleted.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a genuinely empty backup says so instead of pretending', (
    tester,
  ) async {
    serve(jsonEncode({'rounds': []}));

    await openMenuAndImport(tester);
    expect(find.text('That backup is empty.'), findsOneWidget);
    expect(find.text('Restore backup?'), findsNothing);
  });

  testWidgets('a backup already fully present is reported, not restored', (
    tester,
  ) async {
    store.scoreColors = {1: 0xFF00FF00};
    serve(toJson([_round()], [_course()], scoreColors: {1: 0xFF00FF00}));

    await openMenuAndImport(tester);
    expect(find.textContaining('Nothing new'), findsOneWidget);
    expect(find.text('Restore backup?'), findsNothing);
  });

  testWidgets('cancelling the picker does nothing', (tester) async {
    serveNothing();
    await openMenuAndImport(tester);
    expect(find.text('Restore backup?'), findsNothing);
    expect(store.courses.length, 1);
  });
}

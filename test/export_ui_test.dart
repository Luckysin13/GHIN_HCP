import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghin_golf/main.dart';
import 'package:ghin_golf/models.dart';
import 'package:ghin_golf/store.dart';

/// Stands in for the platform's documents directory, so a test export really
/// does write a file and the assertions can read it back.
class _FakeDocs {
  final root = Directory.systemTemp.createTempSync('ghin_export_test');
  late final List<MethodCall> calls = [];
}

/// The channel path_provider_android uses. Mocked at the channel so the test
/// needs no platform-interface packages.
const _docsChannel = MethodChannel('plugins.flutter.io/path_provider');

/// The host's own save dialog, which file_selector does not cover on Android.
const _saveChannel = MethodChannel('ghin_golf/backup');

/// The content uri a mocked save dialog hands back. The host writes the file
/// through ContentResolver, so the bytes do not land in the test's temp dir
/// and [savedContents] is what gets asserted on instead.
const _chosenUri = 'content://downloads/backup.json';

/// Everything the host was asked to write, in order.
final savedContents = <String>[];

void main() {
  late _FakeDocs fake;
  late GolfStore store;

  setUp(() {
    fake = _FakeDocs();
    savedContents.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_saveChannel, (call) async {
          if (call.method == 'pickDestination') return _chosenUri;
          if (call.method == 'writeTo') {
            savedContents.add(call.arguments['contents'] as String);
            return true;
          }
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_docsChannel, (call) async {
          fake.calls.add(call);
          if (call.method == 'getApplicationDocumentsPath') {
            return fake.root.path;
          }
          return null;
        });
    store = GolfStore();
    store.rounds = [
      Round(
        id: 'r1',
        courseId: 'c1',
        teeId: 'tee-White',
        playedAt: DateTime.utc(2026, 9, 20),
        holes: [for (var i = 0; i < 18; i++) HoleScore(score: 4, putts: 2)],
      ),
    ];
    store.courses = [
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
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_docsChannel, null);
    messenger.setMockMethodCallHandler(_saveChannel, null);
    fake.root.deleteSync(recursive: true);
  });

  Widget app() =>
      MaterialApp(home: HomePage(store: store));

  /// The contents the export handed to the platform, waiting for the save
  /// dialog round trip to finish.
  ///
  /// The pick and the write are two awaited channel calls, and pumpAndSettle
  /// only advances frames, so the menu closes before either has run.
  Future<List<String>> written(WidgetTester tester, {int count = 1}) async {
    for (var i = 0; i < 50; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
      if (savedContents.length >= count) return [...savedContents];
    }
    return [...savedContents];
  }

  /// The backup menu, in the app bar so it is reachable without scrolling.
  Finder backupButton() => find.byTooltip('Backup');

  testWidgets('the backup menu offers export and import', (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(backupButton());
    await tester.pumpAndSettle();
    expect(find.text('Export CSV'), findsOneWidget);
    expect(find.text('Export full backup'), findsOneWidget);
    expect(find.text('Import backup'), findsOneWidget);
  });

  testWidgets('the backup menu needs no scrolling to reach', (tester) async {
    // The quick-post card is tall enough to push a footer button off
    // screen, which is why this lives in the app bar.
    await tester.pumpWidget(app());
    expect(find.byType(ListView), findsOneWidget);
    expect(backupButton().evaluate().isNotEmpty, isTrue);
  });

  Future<void> pickFormat(WidgetTester tester, String label) async {
    await tester.tap(backupButton());
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('picking CSV writes readable CSV where the user chose',
      (tester) async {
    await tester.pumpWidget(app());
    await pickFormat(tester, 'Export CSV');

    final files = await written(tester);
    expect(files.length, 1);
    expect(files.single.split('\n').first,
        startsWith('id,played_at,course,tee'));
    expect(files.single, contains('Bent Creek'));
  });

  testWidgets('picking JSON writes a parseable backup', (tester) async {
    await tester.pumpWidget(app());
    await pickFormat(tester, 'Export full backup');

    final files = await written(tester);
    expect(files.length, 1);
    final j = jsonDecode(files.single);
    expect((j['rounds'] as List).length, 1);
  });

  testWidgets('dismissing the menu writes nothing', (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(backupButton());
    await tester.pumpAndSettle();
    // Tap the barrier, not an option.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(savedContents, isEmpty);
  });

  testWidgets('cancelling the save dialog reports no error', (tester) async {
    // Backing out of the save dialog is the user changing their mind, and
    // must not be reported as a failure.
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_saveChannel, (call) async {
      if (call.method == 'pickDestination') return null;
      if (call.method == 'writeTo') {
        savedContents.add(call.arguments['contents'] as String);
        return true;
      }
      return null;
    });
    await tester.pumpWidget(app());
    await pickFormat(tester, 'Export full backup');
    await written(tester, count: 0);
    expect(savedContents, isEmpty);
    expect(find.textContaining('Export failed'), findsNothing);
    expect(find.textContaining('Saved'), findsNothing);
  });

  testWidgets('exporting a second time works the same way', (tester) async {
    // The save dialog is shown each time and the file is written whole, so a
    // second export is not skipped or appended to. Distinct suggested names
    // per minute are covered in export_filename_test.
    await tester.pumpWidget(app());
    await pickFormat(tester, 'Export CSV');
    expect((await written(tester)).length, 1);
    await pickFormat(tester, 'Export CSV');
    final files = await written(tester, count: 2);
    expect(files.length, 2);
    // The second write replaces the first rather than appending to it, so
    // what lands is one whole file and not two spliced together.
    for (final f in files) {
      expect(f.trim().split('\n').length, 2);
    }
  });
}

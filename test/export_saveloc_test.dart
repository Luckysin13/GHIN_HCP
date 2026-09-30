import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghin_golf/export_io.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

const _androidChannel = MethodChannel('ghin_golf/backup');

class _FakeSelector extends FileSelectorPlatform
    with MockPlatformInterfaceMixin {
  /// What getSaveLocation hands back, or null to simulate the user cancelling.
  String? chosen;

  /// Recorded arguments, so the suggested name can be asserted.
  final suggested = <String?>[];

  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async {
    suggested.add(options.suggestedName);
    final p = chosen;
    return p == null ? null : FileSaveLocation(p);
  }
}

class _FakeDocs extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final root = Directory.systemTemp.createTempSync('ghin_saveloc_test');

  @override
  Future<String?> getApplicationDocumentsPath() async => root.path;
}

class _FakeAndroid {
  final picks = <MethodCall>[];
  final writes = <MethodCall>[];

  /// What the save dialog returns: a uri, or null for "user cancelled".
  String? pickResult = 'content://downloads/backup.json';

  /// What ContentResolver reports the write as.
  bool writeResult = true;

  /// Set to make the pick throw, e.g. when a dialog cannot be shown.
  PlatformException? pickError;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_androidChannel, (call) async {
          if (call.method == 'pickDestination') {
            picks.add(call);
            if (pickError != null) throw pickError!;
            return pickResult;
          }
          if (call.method == 'writeTo') {
            writes.add(call);
            return writeResult;
          }
          return null;
        });
  }
}

void main() {
  // The save path goes over platform channels, which need a binding even
  // though nothing here pumps a widget.
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeAndroid android;
  late _FakeSelector selector;
  late _FakeDocs docs;

  setUp(() {
    android = _FakeAndroid()..install();
    selector = _FakeSelector();
    docs = _FakeDocs();
    FileSelectorPlatform.instance = selector;
    PathProviderPlatform.instance = docs;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_androidChannel, null);
    docs.root.deleteSync(recursive: true);
  });

  void asAndroid() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  }

  void asDesktop() {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  }

  group('android save dialog', () {
    setUp(asAndroid);

    test('asks the user, suggesting a timestamped name', () async {
      final r = await writeBackupFile(
        'ghin-golf-rounds-20260928-1842.csv',
        'a,b',
        mimeType: 'text/csv',
      );
      expect(android.picks.single.method, 'pickDestination');
      expect(
        android.picks.single.arguments['suggestedName'],
        'ghin-golf-rounds-20260928-1842.csv',
      );
      expect(r, isA<BackupWritten>());
    });

    test('sends the full contents to the chosen location', () async {
      await writeBackupFile('b.json', '{"rounds":[]}');
      expect(android.writes.single.method, 'writeTo');
      expect(android.writes.single.arguments['contents'], '{"rounds":[]}');
      expect(
        android.writes.single.arguments['uri'],
        'content://downloads/backup.json',
      );
    });

    test('cancelling writes nothing and is not an error', () async {
      android.pickResult = null;
      final r = await writeBackupFile('b.json', 'x');
      expect(r, isA<BackupCancelled>());
      expect(android.writes, isEmpty);
    });

    test('a refused write is reported as a failure, not a success', () async {
      android.writeResult = false;
      final r = await writeBackupFile('b.json', 'x');
      expect(r, isA<BackupFailed>());
    });

    test('an unwritable location never claims success', () async {
      android.writeResult = false;
      final r = await writeBackupFile('b.json', 'x');
      expect(r, isNot(isA<BackupWritten>()));
    });

    test('falls back to Documents when the host has no save dialog', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_androidChannel, null);
      final r = await writeBackupFile('b.json', 'contents here');
      expect(r, isA<BackupWritten>());
      expect(docs.root.listSync().whereType<File>().single.path,
          endsWith('b.json'));
    });

    test('falls back to Documents when the dialog is unavailable', () async {
      android.pickError = PlatformException(code: 'unavailable');
      final r = await writeBackupFile('b.json', 'contents here');
      expect(r, isA<BackupWritten>());
      final f = docs.root.listSync().whereType<File>().single;
      expect(f.readAsStringSync(), 'contents here');
    });

    test('does not write anything when the dialog is dismissed', () async {
      android.pickResult = null;
      await writeBackupFile('b.json', 'x');
      expect(docs.root.listSync().whereType<File>(), isEmpty);
    });
  });

  group('desktop save dialog', () {
    setUp(asDesktop);

    test('writes to the location the user chose', () async {
      final target = '${Directory.systemTemp.path}/ghin_chosen_export.csv';
      selector.chosen = target;
      final r = await writeBackupFile('ghin-rounds.csv', 'id,course\n1,X\n');
      expect(r, isA<BackupWritten>());
      expect(File(target).readAsStringSync(), 'id,course\n1,X\n');
      File(target).deleteSync();
    });

    test('suggests the same timestamped name on desktop', () async {
      selector.chosen = null;
      await writeBackupFile('ghin-rounds-20260928-1842.json', 'x');
      expect(selector.suggested, ['ghin-rounds-20260928-1842.json']);
    });

    test('cancelling writes nothing', () async {
      selector.chosen = null;
      final r = await writeBackupFile('b.csv', 'x');
      expect(r, isA<BackupCancelled>());
      expect(docs.root.listSync().whereType<File>(), isEmpty);
    });

    test('the user can rename it in the dialog', () async {
      // The suggested name is only a default; the whole point of asking is
      // that the chosen name is the one that counts.
      selector.chosen = '${Directory.systemTemp.path}/ghin_my_own_name.csv';
      final r = await writeBackupFile('suggested.csv', 'mine');
      expect((r as BackupWritten).where, endsWith('ghin_my_own_name.csv'));
      File(selector.chosen!).deleteSync();
    });
  });
}

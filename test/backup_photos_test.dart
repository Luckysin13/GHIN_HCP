import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghin_golf/export.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ghin_golf/models.dart';
import 'package:ghin_golf/scan_service.dart';
import 'package:ghin_golf/store.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

const _docsChannel = MethodChannel('plugins.flutter.io/path_provider');

class _FakeDocs extends PathProviderPlatform with MockPlatformInterfaceMixin {
  final root = Directory.systemTemp.createTempSync('ghin_photo_test');

  @override
  Future<String?> getApplicationDocumentsPath() async => root.path;
}

/// A one-pixel JPEG, so the bytes are a real image rather than a stand-in.
final jpegBytes = <int>[
  0xFF,
  0xD8,
  0xFF,
  0xE0,
  0x00,
  0x10,
  0x4A,
  0x46,
  0x49,
  0x46,
  0x00,
  0x01,
  0x01,
  0x00,
  0x00,
  0x01,
  0x00,
  0x01,
  0x00,
  0x00,
  0xFF,
  0xD9,
];

Course _course({
  String id = 'c1',
  String name = 'Cedar Hills',
  String img = '',
}) => Course(
  id: id,
  name: name,
  city: 'Austin',
  state: 'TX',
  tees: [],
  custom: true,
  imagePath: img,
);

Round _round({String id = 'r1', String img = ''}) => Round(
  id: id,
  courseId: 'c1',
  teeId: 'tee-White',
  playedAt: DateTime.utc(2026, 9, 20),
  holes: [for (var i = 0; i < 18; i++) HoleScore(score: 4)],
  imagePath: img,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakeDocs docs;
  late GolfStore store;

  setUp(() {
    docs = _FakeDocs();
    PathProviderPlatform.instance = docs;
    store = GolfStore();
    store.rounds = [_round()];
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_docsChannel, null);
    docs.root.deleteSync(recursive: true);
  });

  group('photo capture', () {
    test('a course photo is inlined in the backup', () async {
      final dir = await scorecardPhotoDirectory();
      final photo = File('${dir.path}/c1.jpg')..writeAsBytesSync(jpegBytes);
      store.courses = [_course(img: photo.path)];

      final j = jsonDecode(store.exportRoundsJson());
      final photos = j['photos'] as Map;
      expect(photos.keys, contains('c1.jpg'));
      expect(base64Decode(photos['c1.jpg'] as String), jpegBytes);
    });

    test('a course with no photo adds nothing', () {
      store.courses = [_course()];
      expect((jsonDecode(store.exportRoundsJson())['photos'] as Map), isEmpty);
    });

    test('a photo path that no longer exists is skipped, not fatal', () {
      // The file may have been cleared; the backup should still be written.
      store.courses = [_course(img: '/nonexistent/gone.jpg')];
      final j = jsonDecode(store.exportRoundsJson());
      expect((j['photos'] as Map), isEmpty);
      expect((j['rounds'] as List).length, 1);
    });

    test('a round photo is inlined under its own key', () async {
      final dir = await scorecardPhotoDirectory();
      final photo = File('${dir.path}/round-r1.jpg')
        ..writeAsBytesSync(jpegBytes);
      store.rounds = [_round(img: photo.path)];

      final j = jsonDecode(store.exportRoundsJson());
      final photos = j['photos'] as Map;
      expect(photos.keys, contains('round-r1.jpg'));
      expect(base64Decode(photos['round-r1.jpg'] as String), jpegBytes);
    });

    test('a picked round photo lands under its round key', () async {
      final src = File('${docs.root.path}/picked.jpg')
        ..writeAsBytesSync(jpegBytes);
      final dest = await persistRoundPhoto(XFile(src.path), 'r9');
      expect(dest, endsWith('round-r9.jpg'));
      expect(File(dest).readAsBytesSync(), jpegBytes);
    });
  });

  group('photo restore', () {
    test('the photo lands on disk and the course points at it', () async {
      final backup = parseBackup(
        toJson(
          [_round()],
          [_course()],
          photos: {'c1.jpg': base64Encode(jpegBytes)},
        ),
      );
      // Start with no courses, so the restored one is added fresh.
      store.courses = [];
      final r = await store.importBackup(backup);

      expect(r.photosRestored, 1);
      final dir = await scorecardPhotoDirectory();
      expect(File('${dir.path}/c1.jpg').readAsBytesSync(), jpegBytes);
      expect(store.courses.single.imagePath, '${dir.path}/c1.jpg');
    });

    test('the restored image is actually readable as a file', () async {
      final backup = parseBackup(
        toJson(
          [_round()],
          [_course()],
          photos: {'c1.jpg': base64Encode(jpegBytes)},
        ),
      );
      store.courses = [];
      await store.importBackup(backup);
      // photoUsable is what the UI checks before showing the thumbnail, so a
      // restore that wrote the wrong bytes would fail here.
      expect(photoUsable(store.courses.single.imagePath), isTrue);
    });

    test('a course whose photo is really on disk keeps it', () async {
      // A real file, not just a path: a path pointing at nothing is a lost
      // photo, and the next test covers that case instead.
      final dir = await scorecardPhotoDirectory();
      final mine = File('${dir.path}/mine.jpg')..writeAsBytesSync(jpegBytes);
      store.courses = [_course(name: 'Has a photo', img: mine.path)];
      final backup = parseBackup(
        toJson(
          [_round()],
          [_course()],
          photos: {'c1.jpg': base64Encode(jpegBytes)},
        ),
      );
      final r = await store.importBackup(backup);
      expect(r.photosRestored, 0, reason: 'the app already has this image');
      expect(store.courses.single.imagePath, mine.path);
    });

    test('a course pointing at a lost file gets the photo back', () async {
      // The path survived but the bytes did not, e.g. the phone's app data
      // was cleared. The backup is exactly what recovers this.
      store.courses = [_course(name: 'Lost its photo', img: '/gone/c1.jpg')];
      final backup = parseBackup(
        toJson(
          [_round()],
          [_course()],
          photos: {'c1.jpg': base64Encode(jpegBytes)},
        ),
      );
      final r = await store.importBackup(backup);
      expect(r.photosRestored, 1);
      final dir = await scorecardPhotoDirectory();
      expect(File('${dir.path}/c1.jpg').readAsBytesSync(), jpegBytes);
      expect(store.courses.single.imagePath, '${dir.path}/c1.jpg');
    });

    test('corrupt base64 never reaches the disk', () async {
      // A truncated photo would otherwise be written out as a broken file.
      final backup = parseBackup(
        jsonEncode({
          'rounds': [],
          'courses': [],
          'photos': {'c1.jpg': 'not base64 at all !!!'},
        }),
      );
      expect(backup.photos, isEmpty);
      store.courses = [];
      final r = await store.importBackup(backup);
      expect(r.photosRestored, 0);
    });

    test('a backup with no photos restores fine', () async {
      final r = await store.importBackup(
        parseBackup(toJson([_round()], [_course()])),
      );
      expect(r.photosRestored, 0);
      expect(r.coursesAdded, 1);
    });

    test('a restored round points at its photo on disk', () async {
      final backup = parseBackup(
        toJson(
          [_round()],
          [_course()],
          photos: {'round-r1.jpg': base64Encode(jpegBytes)},
        ),
      );
      store.rounds = [];
      store.courses = [];
      final r = await store.importBackup(backup);

      expect(r.photosRestored, 1);
      final dir = await scorecardPhotoDirectory();
      expect(File('${dir.path}/round-r1.jpg').readAsBytesSync(), jpegBytes);
      expect(store.rounds.single.imagePath, '${dir.path}/round-r1.jpg');
    });

    test('a round photo for an unrestored round is left alone', () async {
      // Orphan bytes with no round to point at them are skipped, not written.
      final backup = parseBackup(
        toJson(
          [],
          [_course()],
          photos: {'round-ghost.jpg': base64Encode(jpegBytes)},
        ),
      );
      store.rounds = [];
      store.courses = [];
      final r = await store.importBackup(backup);

      expect(r.photosRestored, 0);
      final dir = await scorecardPhotoDirectory();
      expect(File('${dir.path}/round-ghost.jpg').existsSync(), isFalse);
    });
  });

  group('completeness', () {
    test('an older backup on the customCourses key still opens', () async {
      // Files exported before the full snapshot used the old key, and must not
      // come back looking empty.
      final legacy = jsonEncode({
        'exportVersion': 1,
        'rounds': [_round().toJson()],
        'customCourses': [_course().toJson()],
      });
      final b = parseBackup(legacy);
      expect(b.rounds.length, 1);
      expect(b.courses.single.name, 'Cedar Hills');
    });

    test('the app version survives the round trip', () {
      final b = parseBackup(toJson([], [], appVersion: '1.2.3+4'));
      expect(b.appVersion, '1.2.3+4');
    });

    test('a full backup has every key a restore needs', () {
      final j = jsonDecode(store.exportRoundsJson());
      for (final k in [
        'exportVersion',
        'exportedAt',
        'appVersion',
        'rounds',
        'courses',
        'scoreColors',
        'photos',
      ]) {
        expect(j.containsKey(k), isTrue, reason: 'backup is missing $k');
      }
    });

    test('the whole thing round-trips with nothing lost', () {
      final original = GolfStore()
        ..rounds = [_round(id: 'r1'), _round(id: 'r2')]
        ..courses = [
          _course(id: 'c1', name: 'One'),
          _course(id: 'c2', name: 'Two'),
        ];
      original.setScoreColor(-1, 0xFF00FF00);

      final b = parseBackup(original.exportRoundsJson());
      expect(b.rounds.length, 2);
      expect(b.courses.length, 2);
      expect(b.scoreColors![-1], 0xFF00FF00);
    });

    test(
      'every course in the store is in the backup, not just the custom ones',
      () async {
        // The bundled courses are what a posted round resolves its handicap
        // against, so a backup without them restores rounds that no longer add
        // up. Seed courses are non-custom, which is exactly what got left out.
        final seeded = GolfStore().courses;
        expect(seeded, isNotEmpty);
        expect(seeded.any((c) => !c.custom), isTrue);

        final store = GolfStore()..courses = seeded;
        final j = jsonDecode(store.exportRoundsJson());
        final ids = (j['courses'] as List)
            .map((e) => Course.fromJson(Map<String, dynamic>.from(e as Map)).id)
            .toSet();
        expect(ids, seeded.map((c) => c.id).toSet());
      },
    );

    test('every key the save file writes is also in the backup', () async {
      // The save file and the backup are written by different code, which is
      // how a field ends up saved but never backed up. This fails the moment
      // a new piece of state is added to one and not the other.
      GolfStore.testFilePath = '${docs.root.path}/save.json';
      addTearDown(() => GolfStore.testFilePath = null);
      await store.save();
      final save = jsonDecode(File(GolfStore.testFilePath!).readAsStringSync());
      final backup = jsonDecode(store.exportRoundsJson());
      for (final key in save.keys) {
        expect(
          backup.containsKey(key) || key == 'customCourses',
          isTrue,
          reason: '"$key" is saved but not backed up',
        );
      }
    });

    test('a save-file key present but empty in the backup is caught', () async {
      // Key presence alone is not enough: a key written as an empty map is
      // still "present" and would silently drop the user's settings.
      GolfStore.testFilePath = '${docs.root.path}/save.json';
      addTearDown(() => GolfStore.testFilePath = null);
      store.setScoreColor(2, 0xFFABCDEF);
      await store.save();
      final save = jsonDecode(File(GolfStore.testFilePath!).readAsStringSync());
      final backup = jsonDecode(store.exportRoundsJson());
      expect((save['scoreColors'] as Map), isNotEmpty);
      expect(
        backup['scoreColors'],
        save['scoreColors'],
        reason: 'the backup must carry the same colors the save file holds',
      );
    });
  });
}

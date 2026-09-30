import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghin_golf/export.dart';
import 'package:ghin_golf/models.dart';
import 'package:ghin_golf/scan_service.dart';
import 'package:ghin_golf/store.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakeDocs extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final root = Directory.systemTemp.createTempSync('ghin_preview_test');

  @override
  Future<String?> getApplicationDocumentsPath() async => root.path;
}

Course _course({String id = 'c1', String name = 'Cedar Hills', String img = ''}) =>
    Course(
      id: id,
      name: name,
      city: 'Austin',
      state: 'TX',
      tees: [],
      custom: true,
      imagePath: img,
    );

Round _round({String id = 'r1', String courseId = 'c1'}) => Round(
  id: id,
  courseId: courseId,
  teeId: 'tee-White',
  playedAt: DateTime.utc(2026, 9, 20),
  holes: [for (var i = 0; i < 18; i++) HoleScore(score: 4)],
);

final jpegBytes = <int>[0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0xFF, 0xD9];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakeDocs docs;
  late GolfStore store;

  setUp(() {
    docs = _FakeDocs();
    PathProviderPlatform.instance = docs;
    store = GolfStore()..rounds = [_round()];
  });

  tearDown(() => docs.root.deleteSync(recursive: true));

  group('preview counts every kind of content', () {
    test('a backup with no new rounds is not "nothing new"', () {
      // The reported bug: the old gate asked only about rounds, so this
      // reported "nothing new" and the restore never ran, dropping the
      // courses, colors and photos the app was actually missing.
      store.courses = [];
      final b = parseBackup(
        toJson(
          [_round()], // already present
          [_course(name: 'From the backup')],
          scoreColors: {3: 0xFF00FF00},
          photos: {'c1.jpg': base64Encode(jpegBytes)},
        ),
      );

      final p = store.previewBackup(b);
      expect(p.roundsAdded, 0, reason: 'the only round is already here');
      expect(p.coursesAdded, 1);
      expect(p.colorsChanged, greaterThan(0));
      expect(p.photosRestored, 1);
    });

    test('settings alone make a backup worth restoring', () {
      final b = parseBackup(toJson([], [], scoreColors: {2: 0xFF123456}));
      final p = store.previewBackup(b);
      expect(p.roundsAdded, 0);
      expect(p.coursesAdded, 0);
      expect(p.colorsChanged, 1);
    });

    test('a color that already matches is not counted as a change', () {
      store.scoreColors = {1: 0xFFABCDEF};
      final b = parseBackup(toJson([], [], scoreColors: {1: 0xFFABCDEF}));
      expect(store.previewBackup(b).colorsChanged, 0);
    });

    test('a differing color is counted', () {
      store.scoreColors = {1: 0xFFABCDEF};
      final b = parseBackup(toJson([], [], scoreColors: {1: 0xFF000000}));
      expect(store.previewBackup(b).colorsChanged, 1);
    });

    test('a photo the app already has is not counted again', () async {
      final dir = await scorecardPhotoDirectory();
      final photo = File('${dir.path}/c1.jpg')..writeAsBytesSync(jpegBytes);
      store.courses = [_course(img: photo.path)];
      final b = parseBackup(
        toJson([], [_course()], photos: {'c1.jpg': base64Encode(jpegBytes)}),
      );
      expect(store.previewBackup(b).photosRestored, 0);
    });

    test('a photo whose file was lost is counted, it is a real restore', () {
      // imagePath is set but the file is gone, e.g. the phone was wiped.
      store.courses = [_course(img: '/gone/c1.jpg')];
      final b = parseBackup(
        toJson([], [_course()], photos: {'c1.jpg': base64Encode(jpegBytes)}),
      );
      expect(store.previewBackup(b).photosRestored, 1);
    });

    test('a photo with no matching course is ignored', () {
      store.courses = [_course(id: 'other')];
      final b = parseBackup(
        toJson([], [_course()], photos: {'nobody.jpg': base64Encode(jpegBytes)}),
      );
      expect(store.previewBackup(b).photosRestored, 0);
    });
  });

  group('the preview matches what the import actually does', () {
    // The number shown before restoring has to be the number that happens.
    test('counts agree for a mixed backup', () async {
      store.courses = [_course(name: 'Kept')];
      final b = parseBackup(
        toJson(
          [_round(id: 'old'), _round(id: 'new')],
          [_course(name: 'Kept'), _course(id: 'c2', name: 'Added')],
          scoreColors: {0: 0xFF0000FF},
          photos: {'c2.jpg': base64Encode(jpegBytes)},
        ),
      );

      final p = store.previewBackup(b);
      final r = await store.importBackup(b);
      expect(r.added, p.roundsAdded);
      expect(r.skipped, p.roundsSkipped);
      expect(r.coursesAdded, p.coursesAdded);
      expect(r.photosRestored, p.photosRestored);
    });

    test('an unchanged backup previews and imports as zero', () async {
      store.courses = [_course()];
      final b = parseBackup(
        toJson([_round()], [_course()], photos: {}),
      );
      final p = store.previewBackup(b);
      final r = await store.importBackup(b);
      expect(p.roundsAdded, 0);
      expect(p.coursesAdded, 0);
      expect(r.added, 0);
      expect(r.coursesAdded, 0);
      expect(r.photosRestored, 0);
    });

    test('importing twice changes nothing the second time', () async {
      final b = parseBackup(
        toJson(
          [_round(id: 'new')],
          [_course(id: 'c2', name: 'Added')],
          photos: {'c2.jpg': base64Encode(jpegBytes)},
        ),
      );
      final first = store.previewBackup(b);
      expect(first.coursesAdded, 1);
      expect(first.photosRestored, 1);
      await store.importBackup(b);

      // The whole point of skipping known ids.
      final second = store.previewBackup(b);
      expect(second.roundsAdded, 0);
      expect(second.coursesAdded, 0);
      expect(second.photosRestored, 0);
    });
  });

  group('everything really does come back', () {
    test('a settings-only backup applies its colors', () async {
      // The end-to-end version of the bug report: no rounds to add, and the
      // restore still has to happen.
      store.setScoreColor(-1, 0xFF111111);
      final b = parseBackup(toJson([], [], scoreColors: {2: 0xFF00FF00}));
      expect(store.previewBackup(b).colorsChanged, 1);

      final r = await store.importBackup(b);
      expect(r.added, 0);
      expect(store.scoreColorValue(2), 0xFF00FF00);
    });

    test('a course-only backup adds the course and its photo', () async {
      store.courses = [];
      final b = parseBackup(
        toJson([], [_course(name: 'Only a course')], photos: {
          'c1.jpg': base64Encode(jpegBytes),
        }),
      );
      expect(store.previewBackup(b).roundsAdded, 0);
      expect(store.previewBackup(b).coursesAdded, 1);

      await store.importBackup(b);
      expect(store.courses.single.name, 'Only a course');
      final dir = await scorecardPhotoDirectory();
      expect(File('${dir.path}/c1.jpg').readAsBytesSync(), jpegBytes);
      expect(store.courses.single.imagePath, '${dir.path}/c1.jpg');
    });
  });

  group('legacy files', () {
    test('an old customCourses backup previews its courses', () {
      store.courses = [];
      final b = parseBackup(
        jsonEncode({
          'rounds': [_round().toJson()],
          'customCourses': [_course(name: 'Legacy Course').toJson()],
        }),
      );
      expect(b.courses.single.name, 'Legacy Course');
      expect(store.previewBackup(b).coursesAdded, 1);
    });

    test('a file with nothing in it previews as empty', () {
      // Field by field rather than against the whole record: asserting the
      // record itself makes every future field a failing test, which is how a
      // preview field gets added and the check quietly stops meaning "empty".
      final p = store.previewBackup(parseBackup(jsonEncode({'rounds': []})));
      expect(p.roundsAdded, 0);
      expect(p.roundsSkipped, 0);
      expect(p.coursesAdded, 0);
      expect(p.colorsChanged, 0);
      expect(p.photosRestored, 0);
      expect(p.themeChanged, isFalse);
    });
  });
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ghin_golf/course_catalog.dart';
import 'package:ghin_golf/main.dart';
import 'package:ghin_golf/models.dart';
import 'package:ghin_golf/opengolf.dart';
import 'package:ghin_golf/store.dart';

const _stateCsv = '''
course_id,state,tee_name,gender,par,course_rating,slope_rating,front9_rating,front9_slope,back9_rating,back9_slope,bogey_rating,bogey_f9,bogey_b9
100,MN,Blue,M,72,71.2,128,35.4,125,35.8,130,94.3,47.1,47.2
100,MN,Blue,F,72,72.1,131,35.9,129,36.2,133,99.2,49.8,49.4
200,MN,Red,M,35,33.2,111,33.2,111,,,46.2,,
300,MN,Short 18,M,54,50.2,78,25.1,77,,,,,
400,WI,Bad,M,72,70.0,200,35.0,120,35.0,120,,,
500,MN,Par 3,M,27,23.5,70,23.5,70,,,,,
600,MN,Championship,M,72,87.8,155,43.9,155,43.9,155,120.1,60.0,60.1
''';

class _StringAssetBundle extends CachingAssetBundle {
  final Map<String, String> files;
  _StringAssetBundle(this.files);

  @override
  Future<ByteData> load(String key) async {
    final contents = files[key];
    if (contents == null) throw FlutterError('Missing test asset: $key');
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(contents)));
  }
}

void main() {
  test(
    'full catalog import keeps every tee and adds matching online holes',
    () {
      const courseId = 'ncrdb-mn-100';
      const localTees = [
        CourseCatalogTee(
          courseId: '100',
          name: 'Blue',
          gender: 'M',
          holes: 9,
          par: 36,
          rating: 35.4,
          slope: 125,
        ),
        CourseCatalogTee(
          courseId: '100',
          name: 'Red',
          gender: 'F',
          holes: 9,
          par: 35,
          rating: 36.1,
          slope: 129,
        ),
        CourseCatalogTee(
          courseId: '100',
          name: 'Gold',
          gender: 'M',
          holes: 9,
          par: 35,
          rating: 34.2,
          slope: 119,
        ),
      ];
      final result = buildCourseCatalogTeeImport(
        courseId: courseId,
        catalogTees: localTees,
        onlineTees: const [
          OpenGolfTee(
            key: 'blue-male',
            name: 'Blue',
            color: 'blue',
            gender: 'Male',
            rating: 0,
            slope: 0,
            par: 36,
            yardage: 3000,
          ),
          OpenGolfTee(
            key: 'red-female',
            name: 'Red',
            color: 'red',
            gender: 'Female',
            rating: 0,
            slope: 0,
            par: 35,
            yardage: 2700,
          ),
        ],
        onlineHoles: [
          for (var number = 1; number <= 9; number++)
            OpenGolfHoleFull(
              number: number,
              par: number == 1 ? 3 : 4,
              handicapIndex: number,
              yardages: {'blue': 300 + number, 'red': 270 + number},
            ),
        ],
      );

      expect(result.tees, hasLength(3));
      expect(result.tees.map((tee) => tee.name), [
        'Blue (Men)',
        'Red (Women)',
        'Gold (Men)',
      ]);
      expect(result.tees.first.rating, 35.4);
      expect(result.tees.first.slope, 125);
      expect(result.tees.first.holes.first.par, 3);
      expect(result.tees.first.holes.first.yardage, 301);
      expect(result.tees[1].holes.first.yardage, 271);
      expect(result.tees.last.holes.first.par, 4);
      expect(result.tees.last.holes.first.yardage, 0);
      expect(result.teesWithOnlinePars, 2);
      expect(result.teesWithYardage, 2);
      expect(result.onlineStatus, contains('pars for 2 of 3 tees'));
    },
  );

  test('online course matching requires exact name and state', () {
    const local = CourseCatalogCourse(
      state: 'MN',
      sourceId: '100',
      facilityName: 'Bluewater Club',
      name: 'Bluewater Club',
      city: 'Lake City',
    );
    const wrongState = OpenGolfCourse(
      id: 'wrong',
      name: 'Bluewater Club',
      city: 'Lake City',
      state: 'WI',
    );
    const exact = OpenGolfCourse(
      id: 'exact',
      name: 'Bluewater Club',
      city: 'Nearby Township',
      state: 'MN',
    );
    expect(matchOnlineCatalogCourse(local, [wrongState]), isNull);
    expect(matchOnlineCatalogCourse(local, [wrongState, exact]), exact);
  });

  test(
    'missing online hole pars remain flagged, not silently treated as par 4',
    () {
      const tee = CourseCatalogTee(
        courseId: '100',
        name: 'Blue',
        gender: 'M',
        holes: 2,
        par: 7,
        rating: 7,
        slope: 100,
      );
      final imported = buildCourseCatalogTeeImport(
        courseId: 'test',
        catalogTees: [tee],
        onlineTees: const [
          OpenGolfTee(
            key: 'blue-male',
            name: 'Blue',
            gender: 'Male',
            rating: 0,
            slope: 0,
            par: 7,
            yardage: 500,
          ),
        ],
        onlineHoles: const [
          OpenGolfHoleFull(number: 1, par: 3, handicapIndex: 1),
          OpenGolfHoleFull(number: 2, par: 4, hasPar: false, handicapIndex: 2),
        ],
      );
      expect(imported.tees.single.holes.map((hole) => hole.par), [3, 4]);
      expect(imported.missingParHolesByTee['Blue (Men)'], [2]);
      expect(imported.teesWithOnlinePars, 0);
    },
  );

  test('course catalog index searches across course, city and state', () {
    final catalog = CourseRatingCatalog.fromIndexJson(
      jsonEncode({
        'stateFiles': {'MN': 'tees_minnesota.csv'},
        'courses': [
          ['MN', '100', 'Bluewater Club', 'Bluewater Club', 'Lake City'],
          ['WI', '200', 'Bluewater Hills', 'Bluewater Hills', 'Madison'],
          ['MN', '300', 'Oak Course', 'Oak Course', 'Bluewater'],
        ],
      }),
    );

    expect(catalog.search('bluewater').map((course) => course.sourceId), [
      '100',
      '200',
      '300',
    ]);
    expect(catalog.search('lake mn').map((course) => course.sourceId), ['100']);
    expect(catalog.search('bluewater', limit: 2), hasLength(2));
    expect(catalog.search(''), isEmpty);
  });

  test(
    'state tee records preserve gender, nine-hole ratings and nine splits',
    () {
      final tees = parseCourseCatalogTeeCsv(_stateCsv, 'MN');

      expect(tees, hasLength(6));
      expect(tees.first.displayName, 'Blue (Men)');
      expect(tees.first.holes, 18);
      expect(tees.first.par, 72);
      expect(tees.first.rating, 71.2);
      expect(tees.first.slope, 128);
      expect(tees.first.bogeyRating, 94.3);
      expect(tees.first.frontNineRating, 35.4);
      expect(tees.first.frontNineSlope, 125);
      expect(tees.first.frontNineBogeyRating, 47.1);
      expect(tees.first.backNineRating, 35.8);
      expect(tees.first.backNineSlope, 130);
      expect(tees.first.backNineBogeyRating, 47.2);

      final nineHole = tees.singleWhere((tee) => tee.courseId == '200');
      expect(nineHole.holes, 9);
      expect(nineHole.rating, 33.2);
      expect(nineHole.slope, 111);
      expect(nineHole.frontNineRating, isNull);

      final short18 = tees.singleWhere((tee) => tee.courseId == '300');
      expect(short18.holes, 18);
      expect(short18.rating, 50.2);

      final parThree = tees.singleWhere((tee) => tee.courseId == '500');
      expect(parThree.rating, 23.5);
      final championship = tees.singleWhere((tee) => tee.courseId == '600');
      expect(championship.rating, 87.8);
      expect(championship.frontNineRating, 43.9);

      // An invalid slope is excluded rather than offered as a usable rating.
      expect(tees.any((tee) => tee.courseId == '400'), isFalse);
    },
  );

  test('catalog parser rejects a state file with missing required columns', () {
    expect(
      () => parseCourseCatalogTeeCsv('course_id,state\n1,MN\n', 'MN'),
      throwsA(isA<CourseCatalogFormatException>()),
    );
  });

  test('bundled data can find and load a Minnesota course rating', () async {
    final catalog = await CourseRatingCatalog.load();
    expect(catalog.courses.length, greaterThan(14000));

    final course = catalog.search('Adrian Country Club MN').first;
    final tees = await catalog.teesFor(course);
    final blue = tees.singleWhere(
      (tee) => tee.name == 'Blue' && tee.gender == 'M',
    );
    expect(blue.rating, 71.7);
    expect(blue.slope, 121);
    expect(blue.bogeyRating, 94.2);
    expect(blue.frontNineRating, 35.8);
    expect(blue.frontNineBogeyRating, 47.3);
    expect(blue.backNineRating, 35.9);
    expect(blue.backNineBogeyRating, 46.9);
    expect(blue.backNineSlope, 118);
  });

  testWidgets('Courses page surfaces local catalog matches while typing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final catalog = CourseRatingCatalog.fromIndexJson(
      jsonEncode({
        'stateFiles': {'MN': 'tees_minnesota.csv'},
        'courses': [
          ['MN', '576', 'Adrian Country Club', 'Adrian Country Club', 'Adrian'],
        ],
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CoursesPage(store: GolfStore(), catalog: catalog),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('course-search')),
      'Adrian Country Club',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('LOCAL COURSE RATINGS'), findsOneWidget);
    expect(find.textContaining('Online matches'), findsNothing);
    expect(find.text('No course-rating matches.'), findsNothing);
    expect(find.textContaining('Course catalog unavailable:'), findsNothing);
    expect(find.text('Adrian Country Club'), findsWidgets);
    expect(find.text('Import'), findsWidgets);
  });

  testWidgets('adding a catalog course preloads every tee and online holes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final catalog = CourseRatingCatalog.fromIndexJson(
      jsonEncode({
        'stateFiles': {'MN': 'tees_minnesota.csv'},
        'courses': [
          ['MN', '576', 'Adrian Country Club', 'Adrian Country Club', 'Adrian'],
        ],
      }),
      bundle: _StringAssetBundle({
        'assets/course_catalog/tees_minnesota.csv': '''
course_id,state,tee_name,gender,par,course_rating,slope_rating
576,MN,Blue,M,72,71.7,121
576,MN,White,M,72,70.0,118
576,MN,Gold,M,72,64.9,107
576,MN,White,F,72,75.8,125
576,MN,Red,F,72,72.0,119
''',
      }),
    );
    final onlineClient = MockClient((request) async {
      if (request.url.path.endsWith('/courses/search')) {
        return http.Response(
          jsonEncode({
            'courses': [
              {
                'id': 'online-576',
                'name': 'Adrian Country Club',
                'city': 'Adrian',
                'state': 'MN',
              },
            ],
          }),
          200,
        );
      }
      if (request.url.path.endsWith('/online-576/tees')) {
        return http.Response(
          jsonEncode({
            'tees': [
              for (final entry in [
                ('blue', 'Blue', 'Male'),
                ('white', 'White', 'Male'),
                ('gold', 'Gold', 'Male'),
                ('white', 'White', 'Female'),
                ('red', 'Red', 'Female'),
              ])
                {
                  'tee_key': '${entry.$1}-${entry.$3.toLowerCase()}',
                  'tee_name': entry.$2,
                  'tee_color': entry.$1,
                  'gender': entry.$3,
                  'course_rating': null,
                  'slope': null,
                  'par': 72,
                  'yardage': 6500,
                },
            ],
          }),
          200,
        );
      }
      if (request.url.path.endsWith('/online-576/holes')) {
        return http.Response(
          jsonEncode({
            'holes': [
              for (var number = 1; number <= 18; number++)
                {
                  'number': number,
                  if (number != 2)
                    'par': number == 1
                        ? 3
                        : number == 2
                        ? 5
                        : 4,
                  'handicap_index': number,
                  'yardages': {
                    'blue': 300 + number,
                    'white': 280 + number,
                    'gold': 250 + number,
                    'red': 220 + number,
                  },
                },
            ],
          }),
          200,
        );
      }
      return http.Response('{}', 404);
    });
    final store = GolfStore();
    await tester.pumpWidget(
      MaterialApp(
        home: CoursesPage(
          store: store,
          catalog: catalog,
          openGolfApi: OpenGolfApi(client: onlineClient),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('course-search')),
      'Adrian Country Club MN',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Import').first);
    for (
      var attempt = 0;
      attempt < 200 && !tester.any(find.text('Add local course'));
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Add local course'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));

    await tester.scrollUntilVisible(
      find.text('Save course'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Save course'));
    await tester.pumpAndSettle();
    final saved = store.courseById('ncrdb-mn-576')!;
    expect(saved.tees.map((tee) => tee.name), [
      'Blue (Men)',
      'White (Men)',
      'Gold (Men)',
      'White (Women)',
      'Red (Women)',
    ]);
    expect(saved.tees.map((tee) => tee.rating), [71.7, 70, 64.9, 75.8, 72]);
    expect(saved.tees.map((tee) => tee.holes.first.par), [3, 3, 3, 3, 3]);
    expect(saved.tees.map((tee) => tee.holes[1].par), [4, 4, 4, 4, 4]);
    expect(saved.tees.map((tee) => tee.holes.first.yardage), [
      301,
      281,
      251,
      281,
      221,
    ]);
  });

  testWidgets('catalog tee prefills ratings and saves without par confirmation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const course = CourseCatalogCourse(
      state: 'MN',
      sourceId: '123',
      facilityName: 'Practice Club',
      name: 'Practice Club',
      city: 'Town',
    );
    const tee = CourseCatalogTee(
      courseId: '123',
      name: 'Blue',
      gender: 'M',
      holes: 18,
      par: 72,
      rating: 71.2,
      slope: 128,
      frontNineRating: 35.4,
      frontNineSlope: 125,
      backNineRating: 35.8,
      backNineSlope: 130,
    );
    Course? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                Navigator.of(context)
                    .push<Course>(
                      MaterialPageRoute(
                        builder: (_) => AddCourseScreen(
                          catalogCourse: course,
                          catalogTee: tee,
                        ),
                      ),
                    )
                    .then((value) => saved = value);
              },
              child: const Text('Open catalog entry'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open catalog entry'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('you can save now and edit later'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Look up published ratings in the USGA database'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.scrollUntilVisible(
      find.text('Front 9 rating'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Front 9 rating'), findsOneWidget);
    expect(find.text('Teebox 1'), findsOneWidget);
    expect(
      find.text(
        'Published 9-hole ratings are required to include nine-hole scores in the index',
      ),
      findsNothing,
    );
    expect(
      find.text(
        'The database opens separately; enter its published front/back values above.',
      ),
      findsNothing,
    );
    expect(
      find.text('Look up published ratings in the USGA database'),
      findsOneWidget,
    );
    final ratingField = tester.widget<TextField>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'Rating *',
      ),
    );
    expect(ratingField.controller?.text, '71.2');
    final expectedNineFields = {
      'Front 9 rating': '35.4',
      'Front 9 slope': '125',
      'Back 9 rating': '35.8',
      'Back 9 slope': '130',
    };
    for (final entry in expectedNineFields.entries) {
      await tester.scrollUntilVisible(
        find.text(entry.key),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      final field = tester.widget<TextField>(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.labelText == entry.key,
        ),
      );
      expect(field.controller?.text, entry.value, reason: entry.key);
    }

    final saveButton = find.text('Save course');
    await tester.scrollUntilVisible(
      saveButton,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.id, 'ncrdb-mn-123');
    expect(saved!.tees.single.rating, 71.2);
    expect(saved!.tees.single.frontNineRating, 35.4);
    expect(saved!.tees.single.frontNineSlope, 125);
    expect(saved!.tees.single.backNineRating, 35.8);
    expect(saved!.tees.single.backNineSlope, 130);
    expect(saved!.tees.single.holes.length, 18);
    final restored = Course.fromJson(
      jsonDecode(jsonEncode(saved!.toJson())) as Map<String, dynamic>,
    );
    expect(restored.tees.single.frontNineRating, 35.4);
    expect(restored.tees.single.frontNineSlope, 125);
    expect(restored.tees.single.backNineRating, 35.8);
    expect(restored.tees.single.backNineSlope, 130);
  });

  testWidgets(
    'selected catalog tee fills missing splits on an existing course',
    (tester) async {
      const catalogTee = CourseCatalogTee(
        courseId: '123',
        name: 'Blue',
        gender: 'M',
        holes: 18,
        par: 72,
        rating: 71.2,
        slope: 128,
        frontNineRating: 35.4,
        frontNineSlope: 125,
        backNineRating: 35.8,
        backNineSlope: 130,
      );
      final existing = Course(
        id: 'ncrdb-mn-123',
        name: 'Practice Club',
        city: 'Town',
        state: 'MN',
        custom: true,
        tees: [
          Tee(
            id: 'ncrdb-mn-123-blue-men',
            name: 'Blue (Men)',
            rating: 71.2,
            slope: 128,
            frontNineRating: 34.9,
            backNineSlope: 119,
            holes: [
              for (var i = 0; i < 18; i++)
                HoleInfo(number: i + 1, par: 4, yardage: 0, strokeIndex: i + 1),
            ],
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AddCourseScreen(existing: existing, catalogTee: catalogTee),
        ),
      );
      await tester.pumpAndSettle();

      final expectedFields = {
        'Front 9 rating': '34.9',
        'Front 9 slope': '125',
        'Back 9 rating': '35.8',
        'Back 9 slope': '119',
      };
      for (final entry in expectedFields.entries) {
        await tester.scrollUntilVisible(
          find.text(entry.key),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        final field = tester.widget<TextField>(
          find.byWidgetPredicate(
            (widget) =>
                widget is TextField &&
                widget.decoration?.labelText == entry.key,
          ),
        );
        expect(field.controller?.text, entry.value, reason: entry.key);
      }
    },
  );
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ghin_golf/app_theme.dart';
import 'package:ghin_golf/design_tokens.dart';
import 'package:ghin_golf/main.dart';
import 'package:ghin_golf/models.dart';
import 'package:ghin_golf/store.dart';

Course _namedCourse(String id, String name) {
  final seed = GolfStore().courseById('crystal-lake')!;
  return Course(
    id: id,
    name: name,
    city: 'Austin',
    state: 'TX',
    custom: true,
    tees: [
      Tee(
        id: '$id-white',
        name: 'White',
        rating: seed.defaultTee.rating,
        slope: seed.defaultTee.slope,
        holes: seed.defaultTee.holes,
      ),
    ],
  );
}

GolfStore _storeWith(int extraCourses) {
  final store = GolfStore();
  for (var i = 1; i <= extraCourses; i++) {
    store.addCourse(_namedCourse('course-$i', 'Course $i'));
  }
  return store;
}

Future<void> _pumpCourses(WidgetTester tester, GolfStore store) async {
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: CoursesPage(store: store),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('edit button sits left of delete and opens the editor', (
    tester,
  ) async {
    await _pumpCourses(tester, _storeWith(1));

    final edit = find.byKey(const ValueKey('edit-course-course-1'));
    final remove = find.byKey(const ValueKey('delete-course-course-1'));
    expect(edit, findsOneWidget);
    expect(remove, findsOneWidget);
    expect(tester.getCenter(edit).dx, lessThan(tester.getCenter(remove).dx));

    await tester.tap(edit);
    await tester.pumpAndSettle();
    expect(find.text('Edit course'), findsOneWidget);
  });

  testWidgets('delete button asks for confirmation', (tester) async {
    await _pumpCourses(tester, _storeWith(1));

    await tester.tap(find.byKey(const ValueKey('delete-course-course-1')));
    await tester.pumpAndSettle();
    expect(find.text('Delete Course 1?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('course-name-course-1')), findsOneWidget);
  });

  testWidgets('five saved courses still render as cards', (tester) async {
    await _pumpCourses(tester, _storeWith(4));

    expect(find.byKey(const ValueKey('course-dropdown')), findsNothing);
    expect(
      find.byKey(const ValueKey('course-name-crystal-lake')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('course-name-course-4')), findsOneWidget);
  });

  testWidgets('six saved courses collapse into a dropdown', (tester) async {
    final store = _storeWith(5);
    await _pumpCourses(tester, store);

    expect(find.byKey(const ValueKey('course-dropdown')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('course-name-crystal-lake')),
      findsNothing,
    );

    // The dropdown drives the same selection the cards did: picking a
    // course repoints the scorecard below and the edit/delete buttons.
    await tester.tap(find.byKey(const ValueKey('course-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Course 3').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('edit-course-course-3')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('delete-course-course-3')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('edit-course-course-3')));
    await tester.pumpAndSettle();
    expect(find.text('Edit course'), findsOneWidget);
  });

  testWidgets('tee dropdown renders with an outline', (tester) async {
    await _pumpCourses(tester, GolfStore());

    final field = find.byKey(const ValueKey('tee-dropdown-crystal-lake'));
    expect(field, findsOneWidget);
    final decorator = tester.widget<InputDecorator>(
      find.descendant(of: field, matching: find.byType(InputDecorator)),
    );
    expect(decorator.decoration.border, isA<OutlineInputBorder>());
    expect(find.text('Teebox'), findsWidgets);
  });

  testWidgets('course rows use halved padding', (tester) async {
    await _pumpCourses(tester, GolfStore());

    final title = find.byKey(const ValueKey('course-name-crystal-lake'));
    final card = tester.widget<Card>(
      find.ancestor(of: title, matching: find.byType(Card)),
    );
    expect(card.margin, const EdgeInsets.only(top: Insets.xs));

    final tile = tester.widget<ListTile>(
      find.ancestor(of: title, matching: find.byType(ListTile)),
    );
    expect(
      tile.contentPadding,
      const EdgeInsets.symmetric(horizontal: Insets.sm),
    );
  });

  testWidgets('scorecard renders inside an outline', (tester) async {
    await _pumpCourses(tester, GolfStore());

    final outline = tester.widget<Container>(
      find.byKey(const ValueKey('scorecard-outline')),
    );
    final decoration = outline.decoration! as BoxDecoration;
    expect(decoration.border, isNotNull);
  });

  testWidgets('each tee option carries its own border', (tester) async {
    final store = GolfStore();
    final teeId = store.courseById('crystal-lake')!.tees.first.id;
    await _pumpCourses(tester, store);

    await tester.tap(find.byKey(const ValueKey('tee-dropdown-crystal-lake')));
    await tester.pumpAndSettle();

    final option = tester.widget<Container>(
      find.byKey(ValueKey('tee-option-$teeId')),
    );
    final decoration = option.decoration! as BoxDecoration;
    expect(decoration.border, isNotNull);
  });

  testWidgets('a course without a photo offers saving one', (tester) async {
    await _pumpCourses(tester, GolfStore());

    expect(find.text('Save Blank Scorecard'), findsOneWidget);
    expect(find.text('View Scorecard Photo'), findsNothing);

    await tester.tap(find.text('Save Blank Scorecard'));
    await tester.pumpAndSettle();
    expect(find.text('Take photo'), findsOneWidget);
    expect(find.text('Choose from gallery'), findsOneWidget);
  });

  testWidgets('a course with a photo offers viewing it', (tester) async {
    final tmp = Directory.systemTemp.createTempSync('ghin_course_photo');
    addTearDown(() => tmp.deleteSync(recursive: true));
    // A real decodable PNG: the viewer actually renders these bytes.
    final photo = File('${tmp.path}/c1.png')
      ..writeAsBytesSync(
        File(
          'android/app/src/main/res/mipmap-mdpi/ic_launcher.png',
        ).readAsBytesSync(),
      );
    final store = GolfStore();
    final seed = store.courseById('crystal-lake')!;
    store.courses = [seed.copyWithImagePath(photo.path)];
    await _pumpCourses(tester, store);

    expect(find.text('View Scorecard Photo'), findsOneWidget);
    expect(find.text('Save Blank Scorecard'), findsNothing);

    await tester.tap(find.text('View Scorecard Photo'));
    await tester.pumpAndSettle();
    expect(find.text('Crystal Lake Golf Club — scorecard'), findsOneWidget);
    expect(find.byTooltip('Delete photo'), findsOneWidget);
  });
}

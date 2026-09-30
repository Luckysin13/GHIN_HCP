import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ghin_golf/main.dart';
import 'package:ghin_golf/store.dart';

/// Layout scaling guard: every primary screen must build clean at a
/// compact phone size (320x568 logical) with no RenderFlex overflow.
Future<void> pumpAtSize(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(320 * 3, 568 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pump();
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('Home scales to compact width', (tester) async {
    await pumpAtSize(tester, HomePage(store: GolfStore()));
  });

  testWidgets('Post scales to compact width', (tester) async {
    await pumpAtSize(tester, PostPage(store: GolfStore()));
  });

  testWidgets('Courses scales to compact width', (tester) async {
    await pumpAtSize(tester, CoursesPage(store: GolfStore()));
  });

  testWidgets('Stats scales to compact width', (tester) async {
    await pumpAtSize(tester, StatsPage(store: GolfStore()));
  });

  testWidgets('AddCourse scales to compact width', (tester) async {
    await pumpAtSize(tester, const AddCourseScreen());
  });
}

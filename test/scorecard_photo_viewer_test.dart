import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghin_golf/main.dart';

void main() {
  testWidgets('scorecard viewer supports gestures and bounded zoom controls', (
    tester,
  ) async {
    final photo = File(
      'android/app/src/main/res/mipmap-mdpi/ic_launcher.png',
    ).absolute;
    expect(photo.existsSync(), isTrue);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () =>
                    showCoursePhoto(context, 'Crystal Lake', photo.path),
                child: const Text('Open scorecard'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open scorecard'));
    await tester.pumpAndSettle();

    final viewerFinder = find.byKey(
      const ValueKey('scorecard-interactive-viewer'),
    );
    final viewer = tester.widget<InteractiveViewer>(viewerFinder);
    expect(viewer.panEnabled, isTrue);
    expect(viewer.scaleEnabled, isTrue);
    expect(viewer.minScale, 1);
    expect(viewer.maxScale, 6);
    expect(find.text('100%'), findsOneWidget);

    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pumpAndSettle();
    expect(find.text('150%'), findsOneWidget);

    await tester.tap(find.byTooltip('Zoom out'));
    await tester.pumpAndSettle();
    expect(find.text('100%'), findsOneWidget);

    final zoomIn = find.widgetWithIcon(IconButton, Icons.zoom_in);
    for (var i = 0; i < 8; i++) {
      if (tester.widget<IconButton>(zoomIn).onPressed == null) break;
      await tester.tap(zoomIn);
      await tester.pumpAndSettle();
    }
    expect(find.text('600%'), findsOneWidget);
    expect(tester.widget<IconButton>(zoomIn).onPressed, isNull);

    await tester.tap(find.byTooltip('Reset zoom and pan'));
    await tester.pumpAndSettle();
    expect(find.text('100%'), findsOneWidget);
    expect(
      tester
          .widget<InteractiveViewer>(viewerFinder)
          .transformationController!
          .value
          .getMaxScaleOnAxis(),
      1,
    );

    await tester.drag(viewerFinder, const Offset(-50, -30));
    await tester.pumpAndSettle();
    final translation = tester
        .widget<InteractiveViewer>(viewerFinder)
        .transformationController!
        .value
        .getTranslation();
    expect(translation.x, isNot(0));
    expect(translation.y, isNot(0));
  });

  testWidgets('viewer delete runs its callback and closes', (tester) async {
    final photo = File(
      'android/app/src/main/res/mipmap-mdpi/ic_launcher.png',
    ).absolute;
    var deleted = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showCoursePhoto(
                  context,
                  'Crystal Lake',
                  photo.path,
                  onDelete: () async => deleted = true,
                ),
                child: const Text('Open scorecard'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open scorecard'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Delete photo'), findsOneWidget);
    await tester.tap(find.byTooltip('Delete photo'));
    await tester.pumpAndSettle();

    expect(deleted, isTrue);
    expect(find.text('Open scorecard'), findsOneWidget);
  });

  testWidgets('viewer without a delete callback stays view-only', (
    tester,
  ) async {
    final photo = File(
      'android/app/src/main/res/mipmap-mdpi/ic_launcher.png',
    ).absolute;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () =>
                    showCoursePhoto(context, 'Crystal Lake', photo.path),
                child: const Text('Open scorecard'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open scorecard'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Delete photo'), findsNothing);
  });
}

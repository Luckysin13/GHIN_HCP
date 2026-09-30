import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:ghin_golf/scan_service.dart';

img.Image _twoTone(int w, int h) {
  final im = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      im.setPixel(
        x,
        y,
        x < w ~/ 2
            ? img.ColorUint8.rgb(50, 60, 70)
            : img.ColorUint8.rgb(200, 210, 220),
      );
    }
  }
  return im;
}

void main() {
  test('preprocess grayscales the image', () {
    final out = preprocessBytes(img.encodePng(_twoTone(8, 4)))!;
    for (var y = 0; y < out.height; y++) {
      for (var x = 0; x < out.width; x++) {
        final p = out.getPixel(x, y);
        expect(p.r, p.g);
        expect(p.g, p.b);
      }
    }
  });

  test('preprocess stretches contrast to the full range', () {
    final out = preprocessBytes(img.encodePng(_twoTone(8, 4)))!;
    var lo = 255, hi = 0;
    for (var y = 0; y < out.height; y++) {
      for (var x = 0; x < out.width; x++) {
        final v = out.getPixel(x, y).r.toInt();
        if (v < lo) lo = v;
        if (v > hi) hi = v;
      }
    }
    expect(lo, 0);
    expect(hi, 255);
  });

  test('preprocess upscales small images to width 2000', () {
    final out = preprocessBytes(img.encodePng(_twoTone(100, 50)))!;
    expect(out.width, 2000);
    expect(out.height, 1000);
  });

  test('preprocess leaves wide images at native width', () {
    final out = preprocessBytes(img.encodePng(_twoTone(4000, 500)))!;
    expect(out.width, 4000);
  });

  test('undecodable bytes yield null without throwing', () {
    expect(preprocessBytes([0, 1, 2, 3, 4]), isNull);
    expect(preprocessBytes([]), isNull);
  });

  group('thresholded variant', () {
    test('reduces the image to ink and paper', () {
      final out = preprocessBytes(
        img.encodePng(_twoTone(8, 4)),
        prep: ImagePrep.thresholded,
      )!;
      final levels = <int>{};
      for (var y = 0; y < out.height; y++) {
        for (var x = 0; x < out.width; x++) {
          levels.add(out.getPixel(x, y).r.toInt());
        }
      }
      // Otsu picks a cut between the two tones, so nothing in between
      // survives: a thresholded card has no mid-greys to blur the edges.
      expect(levels.length, 2);
      expect(levels.every((v) => v == 0 || v == 255), isTrue);
    });

    test('keeps the dark side dark and the light side light', () {
      final out = preprocessBytes(
        img.encodePng(_twoTone(8, 4)),
        prep: ImagePrep.thresholded,
      )!;
      // The dark half of the source is the left half of the upscaled image.
      expect(out.getPixel(out.width ~/ 4, 1).r.toInt(), 0);
      expect(out.getPixel(out.width * 3 ~/ 4, 1).r.toInt(), 255);
    });

    test('upscales small images like the default does', () {
      final out = preprocessBytes(
        img.encodePng(_twoTone(100, 50)),
        prep: ImagePrep.thresholded,
      )!;
      expect(out.width, 2000);
    });

    test('undecodable bytes still yield null', () {
      expect(
        preprocessBytes([0, 1, 2, 3], prep: ImagePrep.thresholded),
        isNull,
      );
    });
  });

  test('the retry ensemble varies preprocessing as well as segmentation', () {
    // Retrying only the page segmentation repeats the same failure, since
    // every attempt would read the same pixels. The first attempt must also
    // be the plain default, so a good first read is never wasted.
    expect(scanVariants.first.prep, ImagePrep.stretched);
    expect(scanVariants.first.psm, isNull);
    expect(scanVariants.length, greaterThan(1));
    // No two attempts may be identical, or the ensemble wastes a pass.
    final keys = scanVariants.map((v) => '${v.prep}/${v.psm}').toSet();
    expect(keys.length, scanVariants.length);
    expect(scanVariants.map((v) => v.prep).toSet().length, greaterThan(1));
    for (final v in scanVariants) {
      expect(v.label, isNotEmpty);
    }
  });
}

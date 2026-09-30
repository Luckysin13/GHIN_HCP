// The generated icons are checked in, so a bad one is a silent regression: a
// launcher bitmap with the ball cropped off looks exactly like a design choice
// until someone installs the app and finds their home screen is a green
// rectangle. The assertions live in tool/check_icon.dart so the generator can
// be run against its own output; this is the version that runs in the gate.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  const legacy = <String, int>{
    'android/app/src/main/res/mipmap-mdpi/ic_launcher.png': 48,
    'android/app/src/main/res/mipmap-hdpi/ic_launcher.png': 72,
    'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png': 96,
    'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png': 144,
    'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png': 192,
    'web/favicon.png': 32,
    'web/icons/Icon-192.png': 192,
    'web/icons/Icon-512.png': 512,
  };

  const adaptive = <String, int>{
    'android/app/src/main/res/mipmap-mdpi/ic_launcher_foreground.png': 108,
    'android/app/src/main/res/mipmap-hdpi/ic_launcher_foreground.png': 162,
    'android/app/src/main/res/mipmap-xhdpi/ic_launcher_foreground.png': 216,
    'android/app/src/main/res/mipmap-xxhdpi/ic_launcher_foreground.png': 324,
    'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_foreground.png': 432,
  };

  const monochrome = <String, int>{
    'android/app/src/main/res/mipmap-mdpi/ic_launcher_monochrome.png': 108,
    'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_monochrome.png': 432,
  };

  const mac = <String, int>{
    'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_16.png': 16,
    'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png': 1024,
  };

  img.Image load(String path) {
    final f = File(path);
    expect(f.existsSync(), isTrue, reason: 'missing $path');
    return img.decodePng(f.readAsBytesSync())!;
  }

  group('launcher icons', () {
    for (final e in legacy.entries) {
      test('${e.key.split('/').last} is a ${e.value}px mark that fits', () {
        final c = load(e.key);
        expect(c.width, e.value);
        expect(c.height, e.value);
        final n = c.width * c.height;

        var white = 0, red = 0, opaque = 0;
        var minX = 1 << 30, minY = 1 << 30, maxX = -1, maxY = -1;
        var sumX = 0.0, sumY = 0.0;
        for (var y = 0; y < c.height; y++) {
          for (var x = 0; x < c.width; x++) {
            final p = c.getPixel(x, y);
            if (p.a < 128) continue;
            opaque++;
            final w = p.r > 200 && p.g > 200 && p.b > 200;
            final r = p.r > 150 && p.g < 110 && p.b < 110;
            if (w || r) {
              if (x < minX) minX = x;
              if (y < minY) minY = y;
              if (x > maxX) maxX = x;
              if (y > maxY) maxY = y;
            }
            if (w) {
              white++;
              sumX += x;
              sumY += y;
            }
            if (r) red++;
          }
        }

        // Opaque all the way to the corners, so a circular mask has something
        // to cut.
        expect(opaque, n, reason: 'not full-bleed');
        // The ball is a shape, not a speck.
        expect(white, greaterThan(n * 0.04), reason: 'ball too small');
        // The flag is worth drawing at all.
        expect(red, greaterThan(n * 0.005), reason: 'flag too small');
        // Inset, so a round mask cannot clip the mark.
        expect(minX, greaterThanOrEqualTo(1));
        expect(minY, greaterThanOrEqualTo(1));
        expect(maxX, lessThan(c.width - 1));
        expect(maxY, lessThan(c.height - 1));
        // Centred enough to look deliberate.
        expect(sumX / white, inInclusiveRange(c.width * 0.3, c.width * 0.7));
        expect(
          sumY / white,
          inInclusiveRange(c.height * 0.25, c.height * 0.75),
        );
        expect(
          (minY + maxY) / 2,
          inInclusiveRange(c.height * 0.46, c.height * 0.54),
          reason: 'artwork is vertically off-center',
        );
      });
    }
  });

  group('adaptive icon', () {
    for (final e in adaptive.entries) {
      test('${e.key.split('/').last} stays in the 72dp safe zone', () {
        final c = load(e.key);
        expect(c.width, e.value);
        final safe = c.width * 72 / 108;
        final pad = (c.width - safe) / 2;
        var outside = 0, visible = 0;
        for (var y = 0; y < c.height; y++) {
          for (var x = 0; x < c.width; x++) {
            if (c.getPixel(x, y).a < 16) continue;
            visible++;
            if (x < pad || x >= pad + safe || y < pad || y >= pad + safe) {
              outside++;
            }
          }
        }
        expect(visible, greaterThan(0), reason: 'empty foreground');
        expect(outside, 0, reason: '$outside px outside the safe zone');
      });
    }

    for (final e in monochrome.entries) {
      test('${e.key.split('/').last} is a flat silhouette', () {
        final c = load(e.key);
        expect(c.width, e.value);
        // Flat means flat: every opaque pixel must be the *same* colour, not
        // merely a pale one. A shape's antialiased edge is partially
        // transparent by definition and the launcher tints using alpha, so
        // only opaque pixels are judged.
        int? refR, refG, refB;
        var shaded = 0, visible = 0;
        for (var y = 0; y < c.height; y++) {
          for (var x = 0; x < c.width; x++) {
            final p = c.getPixel(x, y);
            if (p.a < 200) continue;
            visible++;
            refR ??= p.r.toInt();
            refG ??= p.g.toInt();
            refB ??= p.b.toInt();
            if (p.r != refR || p.g != refG || p.b != refB) shaded++;
          }
        }
        expect(visible, greaterThan(0));
        expect(shaded, 0, reason: '$shaded opaque px are not one colour');
      });
    }
  });

  group('maskable web icons', () {
    for (final n in [192, 512]) {
      test('Icon-maskable-$n is opaque and survives a circular crop', () {
        final c = load('web/icons/Icon-maskable-$n.png');
        expect(c.width, n);
        final r = c.width / 2;
        var transparent = 0, markOutside = 0, mark = 0;
        for (var y = 0; y < c.height; y++) {
          for (var x = 0; x < c.width; x++) {
            final p = c.getPixel(x, y);
            if (p.a < 250) transparent++;
            final isMark =
                (p.r > 200 && p.g > 200 && p.b > 200) ||
                (p.r > 150 && p.g < 110 && p.b < 110);
            if (!isMark) continue;
            mark++;
            final dx = x + 0.5 - r, dy = y + 0.5 - r;
            if (_sqrt(dx * dx + dy * dy) > r * 0.97) markOutside++;
          }
        }
        expect(transparent, 0, reason: 'not opaque to the corners');
        expect(mark, greaterThan(c.width * c.width * 0.02));
        expect(markOutside, 0, reason: 'the mark would be cropped away');
      });
    }
  });

  group('desktop icons', () {
    test('linux has the PNG the runner loads', () {
      final c = load('linux/runner/resources/app_icon.png');
      expect(c.width, 256);
    });

    test('windows has an .ico the resource script names', () {
      final f = File('windows/runner/resources/app_icon.ico');
      expect(f.existsSync(), isTrue);
      final b = f.readAsBytesSync();
      // ICONDIR: reserved 0, type 1, and at least one image.
      expect(b[0], 0);
      expect(b[1], 0);
      expect(b[2], 1);
      expect(b[4], greaterThanOrEqualTo(1));
    });

    for (final e in mac.entries) {
      test('${e.key.split('/').last} is a ${e.value}px icon', () {
        expect(load(e.key).width, e.value);
      });
    }
  });

  test('the adaptive icon is wired up where Android looks for it', () {
    final xml = File(
      'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
    ).readAsStringSync();
    expect(xml, contains('@mipmap/ic_launcher_foreground'));
    expect(xml, contains('@color/ic_launcher_background'));
    expect(xml, contains('@mipmap/ic_launcher_monochrome'));
    final colors = File(
      'android/app/src/main/res/values/colors.xml',
    ).readAsStringSync();
    expect(colors, contains('ic_launcher_background'));
  });
}

double _sqrt(double v) {
  if (v <= 0) return 0;
  var g = v;
  for (var i = 0; i < 40; i++) {
    g = 0.5 * (g + v / g);
  }
  return g;
}

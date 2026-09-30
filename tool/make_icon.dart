// Generates the app icon at every size the platforms ask for.
//
// Run from the project root:  dart run tool/make_icon.dart
//
// The selected Pennant mark combines layered fairway shapes, a flag, and a golf
// ball. It is drawn here so every platform can regenerate the same artwork at
// the sizes and crops its launcher expects.
//
// Nothing in the mark is thinner than 4% of the canvas, because a flag at
// 48px with a 1px pole is a smudge, and the launcher is the one place the app
// is seen before it is opened.
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// The same green the app's light theme uses for its header, darkened for the
/// icon so white artwork on it still has contrast at 48px.
final deepGreen = img.ColorRgb8(0x0B, 0x3D, 0x2E);
final midGreen = img.ColorRgb8(0x11, 0x6B, 0x4A);
final flagRed = img.ColorRgb8(0xD8, 0x3A, 0x2E);
final ballWhite = img.ColorRgb8(0xF7, 0xF9, 0xF7);
final lightFairway = img.ColorRgb8(0xDC, 0xEB, 0xE0);
final midFairway = img.ColorRgb8(0x7B, 0xB8, 0x8A);
final brightFairway = img.ColorRgb8(0x2F, 0x8A, 0x5B);

void main() {
  // Legacy launcher icons: the full mark, inset slightly so the ball does not
  // touch the edge of a circular mask.
  const legacy = <String, int>{
    'android/app/src/main/res/mipmap-mdpi/ic_launcher.png': 48,
    'android/app/src/main/res/mipmap-hdpi/ic_launcher.png': 72,
    'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png': 96,
    'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png': 144,
    'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png': 192,
  };
  for (final entry in legacy.entries) {
    _write(entry.key, _legacy(entry.value), 'legacy launcher');
  }

  // Adaptive layers are 108dp, of which only the middle 72dp survives most
  // masks. The foreground therefore carries the mark smaller than the
  // background would suggest, or the ball gets its edge cropped off.
  const adaptive = <String, int>{
    'android/app/src/main/res/mipmap-mdpi/ic_launcher_foreground.png': 108,
    'android/app/src/main/res/mipmap-hdpi/ic_launcher_foreground.png': 162,
    'android/app/src/main/res/mipmap-xhdpi/ic_launcher_foreground.png': 216,
    'android/app/src/main/res/mipmap-xxhdpi/ic_launcher_foreground.png': 324,
    'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_foreground.png': 432,
  };
  for (final entry in adaptive.entries) {
    _write(entry.key, _foreground(entry.value), 'adaptive foreground');
  }

  const web = <String, int>{
    'web/favicon.png': 32,
    'web/icons/Icon-192.png': 192,
    'web/icons/Icon-512.png': 512,
  };
  for (final entry in web.entries) {
    _write(entry.key, _legacy(entry.value), 'web icon');
  }

  // Maskable web icons get the same generous inset, because a browser can crop
  // a square PWA icon down to a circle.
  for (final size in [192, 512]) {
    _write(
      'web/icons/Icon-maskable-$size.png',
      _maskable(size),
      'maskable web icon',
    );
  }

  // Android 13 themed icons tint this layer and discard its interior detail,
  // so it is a single flat silhouette. Kept at the same inset as the
  // foreground so the themed icon does not sit larger than the normal one.
  const mono = <String, int>{
    'android/app/src/main/res/mipmap-mdpi/ic_launcher_monochrome.png': 108,
    'android/app/src/main/res/mipmap-hdpi/ic_launcher_monochrome.png': 162,
    'android/app/src/main/res/mipmap-xhdpi/ic_launcher_monochrome.png': 216,
    'android/app/src/main/res/mipmap-xxhdpi/ic_launcher_monochrome.png': 324,
    'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_monochrome.png': 432,
  };
  for (final entry in mono.entries) {
    _write(entry.key, _monochrome(entry.value), 'themed icon');
  }

  // macOS reads a fixed iconset. These are the legacy full-bleed form: the
  // 1024 is the one that gets a rounded mask applied by the system, so it is
  // drawn square rather than pre-rounded.
  final mac = <String, int>{
    for (final n in [16, 32, 64, 128, 256, 512, 1024])
      'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_$n.png': n,
  };
  for (final entry in mac.entries) {
    _write(entry.key, _legacy(entry.value), 'macos icon');
  }

  // Desktop runners, which read a single file each.
  _write('linux/runner/resources/app_icon.png', _legacy(256), 'linux icon');
  _writeBytes(
    'windows/runner/resources/app_icon.ico',
    _ico(256),
    'windows icon',
  );
}

/// The whole mark, inset for a square canvas.
img.Image _legacy(int size) => _composed(
  size,
  // 8% inset: enough that a circular mask never clips the ball.
  scale: 0.84,
  background: true,
);

/// The mark alone, for the adaptive foreground.
img.Image _foreground(int size) => _composed(
  size,
  // Keep every pennant edge inside Android's centered 72dp safe zone.
  scale: 0.68,
  background: false,
);

/// The mark on full-bleed green, inset for icons that get cropped hard.
img.Image _maskable(int size) => _composed(size, scale: 0.76, background: true);

/// The mark as one flat shape, for a launcher that tints it.
img.Image _monochrome(int size) {
  final c = img.Image(width: size, height: size, numChannels: 4);
  _drawPennant(
    c,
    cx: size / 2.0,
    cy: _verticalCenter(size, 0.68),
    u: size * 0.68 / 100.0,
    monochrome: true,
  );
  return c;
}

img.Image _composed(
  int size, {
  required double scale,
  required bool background,
}) {
  final c = img.Image(width: size, height: size, numChannels: 4);
  img.fill(c, color: background ? deepGreen : img.ColorRgba8(0, 0, 0, 0));

  if (background) {
    // A diagonal wash rather than a flat fill, so the icon does not read as a
    // plain green square at launcher size. Kept subtle: the ball has to stay
    // the brightest thing on it.
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final t = ((x + y) / (2.0 * size)).clamp(0.0, 1.0);
        c.setPixelRgba(
          x,
          y,
          _mix(midGreen, deepGreen, t).r,
          _mix(midGreen, deepGreen, t).g,
          _mix(midGreen, deepGreen, t).b,
          255,
        );
      }
    }
  }

  _drawPennant(
    c,
    cx: size / 2.0,
    cy: _verticalCenter(size, scale),
    u: size * scale / 100.0,
    monochrome: false,
  );

  return c;
}

double _verticalCenter(int size, double scale) {
  // The artwork spans y=11..85.5, so its midpoint sits 1.75 units above the
  // drawing origin at y=50. Offset the origin to center the visible bounds.
  return size * (0.5 + 1.75 * scale / 100.0);
}

void _drawPennant(
  img.Image c, {
  required double cx,
  required double cy,
  required double u,
  required bool monochrome,
}) {
  final white = img.ColorRgba8(255, 255, 255, 255);
  final light = monochrome ? white : lightFairway;
  final middle = monochrome ? white : midFairway;
  final lower = monochrome ? white : brightFairway;
  final flag = monochrome ? white : flagRed;
  final ball = monochrome ? white : ballWhite;
  final dimple = img.ColorRgba8(0xC5, 0xD2, 0xC9, 255);
  (double, double) point(double x, double y) =>
      (cx + (x - 50) * u, cy + (y - 50) * u);

  _polygon(c, [
    point(17, 30),
    point(82, 30),
    point(61, 50),
    point(17, 50),
  ], light);
  _polygon(c, [
    point(24, 47),
    point(88, 47),
    point(66, 68),
    point(24, 68),
  ], middle);
  _polygon(c, [
    point(38, 64),
    point(70, 64),
    point(51, 84),
    point(38, 84),
  ], lower);

  final poleX = cx + 2 * u;
  _rect(c, poleX - 2.5 * u, cy - 39 * u, poleX + 2.5 * u, cy + 20 * u, white);
  _polygon(c, [
    point(55, 13),
    point(85, 13),
    point(73, 25),
    point(55, 25),
  ], flag);

  final ballCenter = point(32, 71);
  _ellipse(c, ballCenter.$1, ballCenter.$2, 14.5 * u, 14.5 * u, ball);
  if (!monochrome) {
    for (final (x, y) in [(-4.5, -4.0), (3.0, -5.0), (-1.0, 2.0), (4.8, 4.0)]) {
      _ellipse(
        c,
        ballCenter.$1 + x * u,
        ballCenter.$2 + y * u,
        1.8 * u,
        1.8 * u,
        dimple,
      );
    }
  }
}

img.Color _mix(img.Color a, img.Color b, double t) => img.ColorRgba8(
  (a.r + (b.r - a.r) * t).round(),
  (a.g + (b.g - a.g) * t).round(),
  (a.b + (b.b - a.b) * t).round(),
  255,
);

void _ellipse(
  img.Image c,
  double cx,
  double cy,
  double rx,
  double ry,
  img.Color color,
) {
  if (rx <= 0 || ry <= 0) return;
  for (var y = (cy - ry).floor(); y <= (cy + ry).ceil(); y++) {
    if (y < 0 || y >= c.height) continue;
    for (var x = (cx - rx).floor(); x <= (cx + rx).ceil(); x++) {
      if (x < 0 || x >= c.width) continue;
      // 2x2 supersampling on the edge, so the circle is not visibly stepped.
      final hits = [
        for (var oy = 0; oy < 2; oy++)
          for (var ox = 0; ox < 2; ox++)
            () {
              final px = (x + (ox + 0.5) / 2 - cx) / rx;
              final py = (y + (oy + 0.5) / 2 - cy) / ry;
              return px * px + py * py <= 1.0;
            }(),
      ].where((h) => h).length;
      if (hits == 0) continue;
      _blend(c, x, y, color, hits / 4.0, c.getPixel(x, y));
    }
  }
}

void _rect(
  img.Image c,
  double x0,
  double y0,
  double x1,
  double y1,
  img.Color color,
) {
  for (var y = y0.floor(); y < y1.ceil(); y++) {
    if (y < 0 || y >= c.height) continue;
    for (var x = x0.floor(); x < x1.ceil(); x++) {
      if (x < 0 || x >= c.width) continue;
      _blend(c, x, y, color, 1.0, c.getPixel(x, y));
    }
  }
}

void _polygon(img.Image c, List<(double, double)> pts, img.Color color) {
  final minY = pts.map((p) => p.$2).reduce(math.min);
  final maxY = pts.map((p) => p.$2).reduce(math.max);
  for (var y = minY.floor(); y <= maxY.ceil(); y++) {
    if (y < 0 || y >= c.height) continue;
    final xs = <double>[];
    for (var i = 0; i < pts.length; i++) {
      final a = pts[i], b = pts[(i + 1) % pts.length];
      if ((a.$2 <= y && b.$2 > y) || (b.$2 <= y && a.$2 > y)) {
        xs.add(a.$1 + (y - a.$2) / (b.$2 - a.$2) * (b.$1 - a.$1));
      }
    }
    if (xs.length < 2) continue;
    xs.sort();
    for (var x = xs.first.floor(); x <= xs.last.ceil(); x++) {
      if (x < 0 || x >= c.width) continue;
      _blend(c, x, y, color, 1.0, c.getPixel(x, y));
    }
  }
}

void _blend(
  img.Image c,
  int x,
  int y,
  img.Color top,
  double alpha,
  img.Color under,
) {
  final a = (top.a / 255.0) * alpha;
  if (a <= 0) return;
  c.setPixelRgba(
    x,
    y,
    (under.r + (top.r - under.r) * a).round(),
    (under.g + (top.g - under.g) * a).round(),
    (under.b + (top.b - under.b) * a).round(),
    (under.a + (255 - under.a) * a).round(),
  );
}

void _writeBytes(String path, List<int> bytes, String what) {
  final f = File(path);
  f.parent.createSync(recursive: true);
  f.writeAsBytesSync(bytes);
  stdout.writeln('$what: $path (${bytes.length} bytes)');
}

void _write(String path, img.Image image, String what) {
  final f = File(path);
  f.parent.createSync(recursive: true);
  // Android resource names are lowercase with underscores; every path here
  // already is, but an icon silently dropped into a directory the packager
  // ignores is a confusing way to lose an afternoon.
  if (path.startsWith('android/') &&
      !RegExp(r'^[\w/.-]+\.png$').hasMatch(path)) {
    throw StateError('bad android resource name: $path');
  }
  f.writeAsBytesSync(img.encodePng(image));
  stdout.writeln('$what: $path (${image.width}x${image.height})');
}

/// A single-image .ico holding the 256px PNG, which is what the Windows runner
/// template ships and what Explorer scales from.
List<int> _ico(int size) {
  final png = img.encodePng(_legacy(size));
  final header = BytesBuilder(copy: false)
    ..add([0, 0, 1, 0, 1, 0]) // reserved, type=icon, one image
    ..addByte(size >= 256 ? 0 : size)
    ..addByte(size >= 256 ? 0 : size)
    ..addByte(0) // palette
    ..addByte(0) // reserved
    ..add(_u16(1)) // colour planes
    ..add(_u16(32)) // bits per pixel
    ..add(_u32(png.length))
    ..add(_u32(22)); // offset to the image data
  return [...header.takeBytes(), ...png];
}

List<int> _u16(int v) => [v & 0xFF, (v >> 8) & 0xFF];
List<int> _u32(int v) => [
  v & 0xFF,
  (v >> 8) & 0xFF,
  (v >> 16) & 0xFF,
  (v >> 24) & 0xFF,
];

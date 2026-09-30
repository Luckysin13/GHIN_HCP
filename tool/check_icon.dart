// Checks the generated icons are actually usable, since a mark that is off
// canvas, invisible at 48px, or clipped by a launcher's own mask does not look
// wrong in a file listing.
//
// Run from the project root:  dart run tool/check_icon.dart
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// Fails loudly rather than printing a number, so this is worth running in the
/// gate while the artwork is still moving.
void main() {
  _checkLegacy('android/app/src/main/res/mipmap-mdpi/ic_launcher.png');
  _checkLegacy('android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png');
  _checkLegacy('web/favicon.png');
  _checkLegacy('web/icons/Icon-512.png');
  _checkSafeZone(
    'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_foreground.png',
  );
  _checkMaskable('web/icons/Icon-maskable-512.png');
  _checkTransparent(
    'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_foreground.png',
  );
  stdout.writeln('icon checks passed');
}

class Stats {
  int opaque = 0, white = 0, red = 0, green = 0;
  int minX = 1 << 30, minY = 1 << 30, maxX = -1, maxY = -1;
  double whiteSumX = 0, whiteSumY = 0;
}

Stats _scan(img.Image c, {required bool countBackground}) {
  final s = Stats();
  for (var y = 0; y < c.height; y++) {
    for (var x = 0; x < c.width; x++) {
      final p = c.getPixel(x, y);
      if (p.a < 128) continue;
      s.opaque++;
      final isWhite = p.r > 200 && p.g > 200 && p.b > 200;
      final isRed = p.r > 150 && p.g < 110 && p.b < 110;
      final isGreen = p.g > p.r && p.g > p.b;
      if (isWhite) {
        s.white++;
        s.whiteSumX += x;
        s.whiteSumY += y;
      }
      if (isRed) s.red++;
      if (isGreen && countBackground) s.green++;
      // Bounds of the *mark*, not of the background: the green fills the
      // whole canvas by design, so including it would make every icon look
      // like it ran off the edge.
      if (isWhite || isRed) {
        if (x < s.minX) s.minX = x;
        if (y < s.minY) s.minY = y;
        if (x > s.maxX) s.maxX = x;
        if (y > s.maxY) s.maxY = y;
      }
    }
  }
  return s;
}

void _checkLegacy(String path) {
  final c = img.decodePng(File(path).readAsBytesSync())!;
  final n = c.width * c.height;
  final s = _scan(c, countBackground: true);
  final label = path.split('/').last;

  _expect(s.opaque == n, '$label has transparent pixels');
  // The ball should be a real shape, not a dot: at least 4% of the canvas.
  _expect(
    s.white > n * 0.04,
    '$label: ball is only ${(s.white / n * 100).toStringAsFixed(1)}% of the icon',
  );
  // The flag has to be more than a couple of pixels to be worth drawing.
  _expect(s.red > n * 0.005, '$label: flag is only ${s.red}px');
  _expect(s.green > n * 0.4, '$label: background is not green');

  // The ball's centre, and that it sits in the middle-ish rather than in a
  // corner or off the edge.
  final bx = s.whiteSumX / s.white, by = s.whiteSumY / s.white;
  _expect(
    bx > c.width * 0.3 && bx < c.width * 0.7,
    '$label: ball is off-centre horizontally (${bx.toStringAsFixed(1)}/${c.width})',
  );
  _expect(
    by > c.height * 0.25 && by < c.height * 0.75,
    '$label: ball is off-centre vertically (${by.toStringAsFixed(1)}/${c.height})',
  );
  final markCenterY = (s.minY + s.maxY) / 2;
  _expect(
    markCenterY >= c.height * 0.46 && markCenterY <= c.height * 0.54,
    '$label: artwork is vertically off-centre '
    '(${markCenterY.toStringAsFixed(1)}/${c.height})',
  );
  _expect(
    s.maxX < c.width && s.maxY < c.height && s.minX >= 0 && s.minY >= 0,
    '$label: mark runs off the canvas',
  );
  // Inset check: a circular mask eats the corners, so the mark must not reach
  // the very edge.
  _expect(
    s.minX >= 1 && s.minY >= 1 && s.maxX < c.width - 1 && s.maxY < c.height - 1,
    '$label: mark touches the edge and a circular mask will clip it',
  );
  stdout.writeln(
    'ok  $label  ball=${(s.white / n * 100).toStringAsFixed(1)}% '
    'flag=${s.red}px centre=(${bx.toStringAsFixed(0)},${by.toStringAsFixed(0)})',
  );
}

void _checkSafeZone(String path) {
  final c = img.decodePng(File(path).readAsBytesSync())!;
  // Android's adaptive safe zone is the middle 72 of 108dp, and a foreground
  // wider than that gets its edge shaved off by the mask.
  final safe = c.width * 72 / 108;
  final pad = (c.width - safe) / 2;
  var outside = 0, inside = 0;
  for (var y = 0; y < c.height; y++) {
    for (var x = 0; x < c.width; x++) {
      if (c.getPixel(x, y).a < 16) continue;
      final ok = x >= pad && x < pad + safe && y >= pad && y < pad + safe;
      if (ok) {
        inside++;
      } else {
        outside++;
      }
    }
  }
  final total = inside + outside;
  _expect(total > 0, '$path: adaptive foreground is empty');
  _expect(
    outside == 0,
    '$path: ${(outside / total * 100).toStringAsFixed(1)}% of the mark sits '
    'outside Android\'s 72dp safe zone',
  );
  stdout.writeln(
    'ok  ${path.split('/').last}  fully inside the 72dp safe zone',
  );
}

void _checkMaskable(String path) {
  final c = img.decodePng(File(path).readAsBytesSync())!;
  // A maskable icon is *meant* to be full-bleed: the mask supplies the shape,
  // and a transparent corner is what makes these look wrong on Android. So the
  // background is checked for being complete, and the mark is checked for
  // surviving a crop to the inscribed circle.
  var transparent = 0;
  for (var y = 0; y < c.height; y++) {
    for (var x = 0; x < c.width; x++) {
      if (c.getPixel(x, y).a < 250) transparent++;
    }
  }
  _expect(
    transparent == 0,
    '$path: maskable icons must be opaque to the corners, '
    '${transparent}px are not',
  );

  final r = c.width / 2;
  var markOutside = 0, mark = 0;
  for (var y = 0; y < c.height; y++) {
    for (var x = 0; x < c.width; x++) {
      final p = c.getPixel(x, y);
      final isMark =
          p.r > 200 && p.g > 200 && p.b > 200 ||
          (p.r > 150 && p.g < 110 && p.b < 110);
      if (!isMark) continue;
      mark++;
      final dx = x + 0.5 - r, dy = y + 0.5 - r;
      if (math.sqrt(dx * dx + dy * dy) > r * 0.97) markOutside++;
    }
  }
  _expect(mark > c.width * c.width * 0.02, '$path: the mark is missing');
  _expect(
    markOutside == 0,
    '$path: $markOutside of the mark sit outside the circle a mask may '
    'crop to, so the flag would be cut off',
  );
  stdout.writeln('ok  ${path.split('/').last}  opaque, mark survives a crop');
}

/// The two background greens the generator mixes between.
const _bgA = (r: 0x0B, g: 0x3D, b: 0x2E);
const _bgB = (r: 0x11, g: 0x6B, b: 0x4A);

bool _isBackgroundGreen(num r, num g, num b) {
  for (final c in [_bgA, _bgB]) {
    if ((r - c.r).abs() < 26 && (g - c.g).abs() < 26 && (b - c.b).abs() < 26) {
      return true;
    }
  }
  return false;
}

void _checkTransparent(String path) {
  final c = img.decodePng(File(path).readAsBytesSync())!;
  // The adaptive foreground is composited over the background colour, so it
  // must not carry a background of its own or the gradient is drawn twice and
  // the mask edge shows a seam.
  //
  // Matched against the exact greens rather than "anything greenish": the
  // ball's dimples are a pale sage on purpose, and a loose hue test flags them
  // as a background that is not there.
  for (var y = 0; y < c.height; y++) {
    for (var x = 0; x < c.width; x++) {
      final p = c.getPixel(x, y);
      if (p.a < 16) continue;
      _expect(
        !_isBackgroundGreen(p.r, p.g, p.b),
        '$path: foreground has its own background at ($x,$y); it should be '
        'transparent',
      );
    }
  }
  stdout.writeln(
    'ok  ${path.split('/').last}  foreground is transparent-backed',
  );
}

void _expect(bool ok, String why) {
  if (!ok) throw StateError(why);
}

// Locates the popup menu on screen by diffing two screenshots, so a tap can
// be aimed at a real menu item without being able to see the image.
import 'dart:io';

import 'package:image/image.dart';

void main(List<String> args) {
  final before = decodeImage(File(args[0]).readAsBytesSync())!;
  final after = decodeImage(File(args[1]).readAsBytesSync())!;
  final w = before.width, h = before.height;

  var minY = h, maxY = -1, minX = w, maxX = -1, changed = 0;
  final rowCounts = List<int>.filled(h, 0);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final a = before.getPixel(x, y);
      final b = after.getPixel(x, y);
      final d = (a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs();
      if (d > 24) {
        rowCounts[y]++;
        changed++;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
      }
    }
  }
  stdout.writeln('size ${w}x$h  changed px: $changed');
  if (changed == 0) {
    stdout.writeln('screens identical - nothing opened');
    return;
  }
  stdout.writeln('changed bbox: x $minX..$maxX  y $minY..$maxY');
  // Print dense row bands so item boundaries are visible.
  var band = -1;
  for (var y = 0; y < h; y++) {
    final on = rowCounts[y] > 20;
    if (on && band < 0) band = y;
    if (!on && band >= 0) {
      stdout.writeln('band y $band..${y - 1}  (height ${y - band})');
      band = -1;
    }
  }
  if (band >= 0) stdout.writeln('band y $band..${h - 1}');
}

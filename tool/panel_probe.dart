// Finds the popup panel inside a screenshot: the panel is the undimmed
// (brighter) region, everything around it sits under the barrier scrim.
import 'dart:io';

import 'package:image/image.dart';

void main(List<String> args) {
  final img = decodeImage(File(args[0]).readAsBytesSync())!;
  final y0 = int.parse(args[1]), y1 = int.parse(args[2]);
  var minY = 1 << 30, maxY = -1, minX = 1 << 30, maxX = -1;
  for (var y = y0; y < y1 && y < img.height; y++) {
    for (var x = 0; x < img.width; x++) {
      final p = img.getPixel(x, y);
      final lum = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
      if (lum > 150) {
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
      }
    }
  }
  if (maxY < 0) {
    stdout.writeln('no bright panel found in y $y0..$y1');
    return;
  }
  stdout.writeln('panel x $minX..$maxX  y $minY..$maxY');
  final h = maxY - minY + 1;
  stdout.writeln('panel height $h -> 3 items ~${h ~/ 3}px each');
  stdout.writeln('item centres: '
      '${minY + h ~/ 6}, ${minY + h ~/ 2}, ${(minY + h * 5 / 6).round()}');
}

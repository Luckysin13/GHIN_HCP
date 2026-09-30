import 'package:flutter_test/flutter_test.dart';
import 'package:ghin_golf/export_io.dart';

void main() {
  group('backupFilename', () {
    test('names the file for the format and stamps it', () {
      final at = DateTime(2026, 9, 28, 18, 42);
      expect(backupFilename('csv', at: at), 'ghin-golf-rounds-20260928-1842.csv');
      expect(backupFilename('json', at: at), 'ghin-golf-rounds-20260928-1842.json');
    });

    test('zero-pads so the stamp sorts chronologically', () {
      // Without padding, 20260928-942 would read as a 9-hour time and sort
      // wrongly against 20260928-1042.
      final at = DateTime(2026, 1, 2, 3, 4);
      expect(backupFilename('csv', at: at), 'ghin-golf-rounds-20260102-0304.csv');
    });

    test('two exports a minute apart do not collide', () {
      final a = backupFilename('csv', at: DateTime(2026, 9, 28, 18, 41));
      final b = backupFilename('csv', at: DateTime(2026, 9, 28, 18, 42));
      expect(a, isNot(b));
    });

    test('is safe as a filename', () {
      final f = backupFilename('csv');
      expect(f, isNot(contains('/')));
      expect(f, isNot(contains(' ')));
      expect(f, endsWith('.csv'));
    });
  });
}

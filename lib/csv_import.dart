/// Reads a CSV export back into rounds.
///
/// The mirror of [toCsv] in `export.dart`, and deliberately free of Flutter so
/// the parsing can be asserted on directly: a file that imports the wrong
/// numbers is worse than a file that refuses to import, because nothing in the
/// UI would look broken.
///
/// Two rules shape what gets accepted:
///
///  * Course and tee are matched **by name**, not by id. Ids only mean
///    anything inside one app's save file; a spreadsheet has been through
///    Excel, and a CSV from another app is the case this has to survive.
///  * A round is only restored if the scores are actually there. Everything
///    else in the row is a nicety that can be reconstructed or is better
///    unknown than invented.
library;

import 'models.dart';

/// Thrown when a file is not a CSV this app can read.
class CsvFormatException implements Exception {
  final String message;
  const CsvFormatException(this.message);
  @override
  String toString() => message;
}

/// One parsed row, before it has been matched to a course.
class CsvRound {
  /// The file's own id, when it has one. Used to spot a re-import.
  final String? id;

  final DateTime playedAt;
  final String courseName;
  final String teeName;

  /// Scores for the holes played, in order.
  final List<int> scores;

  /// 0-based index of the first hole played.
  final int startHole;

  /// Par for the holes played, when the file carried a total. Null when the
  /// column was empty, which is not the same as zero.
  final int? parTotal;

  final int? courseHandicap;
  final double? indexAtPlay;
  final double? rating;
  final int? slope;
  final bool isTournament;

  const CsvRound({
    required this.playedAt,
    required this.courseName,
    required this.teeName,
    required this.scores,
    this.id,
    this.startHole = 0,
    this.parTotal,
    this.courseHandicap,
    this.indexAtPlay,
    this.rating,
    this.slope,
    this.isTournament = false,
  });

  /// Rebuilds the round this row describes.
  ///
  /// [courseId] and [teeId] are supplied by the caller, which is the only
  /// part that needs the app's own data.
  Round toRound({required String courseId, required String teeId}) => Round(
    id: id ?? _synthesisedId,
    courseId: courseId,
    teeId: teeId,
    playedAt: playedAt,
    format: 'stroke',
    isTournament: isTournament,
    holes: [for (final s in scores) HoleScore(score: s)],
    courseHandicap: courseHandicap,
    handicapIndexAtPlay: indexAtPlay,
    startHole: startHole,
  );

  /// Rows with no id of their own still need one that is stable, so a second
  /// import of the same file is recognised as the same round rather than
  /// doubling it. The starting hole distinguishes equal scores on opposite
  /// nines.
  String get _synthesisedId =>
      'csv-$courseName-$teeName-${playedAt.toIso8601String()}-'
      '$startHole-${scores.join('-')}';
}

/// Splits CSV text into rows of cells.
///
/// Follows RFC 4180: quoted fields may contain commas, newlines and doubled
/// quotes. A spreadsheet is quite capable of putting a newline inside a course
/// name, and a parser that cannot read it will read the rest of the file as one
/// long field and lose the file silently.
List<List<String>> parseCsvTable(String text) {
  // A BOM from Excel, which would otherwise become part of the first header.
  if (text.startsWith('﻿')) text = text.substring(1);

  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  var sawAnyChar = false;

  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (quoted) {
      if (c != '"') {
        cell.write(c);
        continue;
      }
      // A doubled quote is a literal quote; a lone one ends the field.
      if (i + 1 < text.length && text[i + 1] == '"') {
        cell.write('"');
        i++;
      } else {
        quoted = false;
      }
      continue;
    }

    switch (c) {
      case '"':
        quoted = true;
        sawAnyChar = true;
      case ',':
        row.add(cell.toString());
        cell.clear();
        sawAnyChar = true;
      case '\r':
        // Swallow; the \n that follows ends the record. A file saved with
        // classic Mac line endings would otherwise produce empty rows.
        break;
      case '\n':
        row.add(cell.toString());
        cell.clear();
        rows.add(row);
        row = <String>[];
        sawAnyChar = false;
      default:
        cell.write(c);
        sawAnyChar = true;
    }
  }

  if (cell.isNotEmpty || row.isNotEmpty || sawAnyChar) {
    row.add(cell.toString());
    rows.add(row);
  }
  return rows;
}

/// Reads a ghin-golf CSV export.
///
/// Throws [CsvFormatException] with something worth showing the user when the
/// file has no header, has none of the columns a round needs, or has a row
/// whose scores cannot be read as scores.
List<CsvRound> parseCsv(String text) {
  final rows = parseCsvTable(text).where((r) => r.isNotEmpty).toList();
  if (rows.isEmpty) {
    throw const CsvFormatException('That file is empty.');
  }

  final header = rows.first.map((h) => h.trim().toLowerCase()).toList();
  int columnOf(String name) => header.indexOf(name);

  final scoresCol = columnOf('scores');
  final playedCol = columnOf('played_at');
  if (scoresCol < 0 || playedCol < 0) {
    throw const CsvFormatException(
      'That CSV is missing the "played_at" and "scores" columns, '
      'so it is not a ghin-golf export.',
    );
  }

  String cellAt(List<String> row, int index) =>
      index >= 0 && index < row.length ? row[index].trim() : '';

  final out = <CsvRound>[];
  for (final row in rows.skip(1)) {
    final raw = cellAt(row, scoresCol);
    final scores = _scoresFrom(raw);
    if (scores == null || scores.isEmpty) continue;

    final playedAt = _dateFrom(cellAt(row, playedCol));
    // A row with no usable date is dropped: a round with no date cannot enter
    // the handicap index, which is the only thing this app computes.
    if (playedAt == null) continue;

    final startCol = columnOf('start_hole');
    final idCol = columnOf('id');
    final id = cellAt(row, idCol);

    out.add(
      CsvRound(
        // Blank is not an id: a file with an empty id column would otherwise
        // make every row look like the same round.
        id: id.isEmpty ? null : id,
        playedAt: playedAt,
        courseName: _clean(cellAt(row, columnOf('course'))),
        teeName: _clean(cellAt(row, columnOf('tee'))),
        scores: scores,
        startHole: ((_intFrom(cellAt(row, startCol)) ?? 1) - 1).clamp(0, 17),
        parTotal: _intFrom(cellAt(row, columnOf('par'))),
        courseHandicap: _intFrom(cellAt(row, columnOf('course_handicap'))),
        indexAtPlay: _doubleFrom(cellAt(row, columnOf('index_at_play'))),
        rating: _doubleFrom(cellAt(row, columnOf('rating'))),
        slope: _intFrom(cellAt(row, columnOf('slope'))),
        isTournament:
            cellAt(row, columnOf('tournament')).toLowerCase() == 'yes',
      ),
    );
  }

  if (out.isEmpty) {
    throw const CsvFormatException(
      'No rounds in that file. It needs a "scores" column and a date.',
    );
  }
  return out;
}

/// The '?' the exporter writes for a course or tee it could not resolve is
/// not a name, and importing it would create a course called "?".
String _clean(String v) {
  if (v.isEmpty || v == '?') return '';
  return v;
}

/// Space-separated scores, as [toCsv] writes them.
List<int>? _scoresFrom(String raw) {
  if (raw.trim().isEmpty) return null;
  final out = <int>[];
  for (final part in raw.trim().split(RegExp(r'[\s,;]+'))) {
    final n = int.tryParse(part);
    // A score is 1..12. Anything else means the column is not a score column,
    // and guessing would put a wrong number in the handicap average.
    if (n == null || n < 1 || n > 12) return null;
    out.add(n);
  }
  return out;
}

DateTime? _dateFrom(String raw) {
  if (raw.isEmpty) return null;
  final iso = DateTime.tryParse(raw);
  if (iso != null) return iso;
  // A spreadsheet that reformatted the date into something local and
  // unparseable is common; accept the obvious day-first forms before giving up.
  final m = RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})').firstMatch(raw);
  if (m == null) return null;
  final a = int.parse(m.group(1)!), b = int.parse(m.group(2)!);
  var y = int.parse(m.group(3)!);
  if (y < 100) y += y < 70 ? 2000 : 1900;
  // Unambiguous only when one field cannot be a month.
  final (d, mo) = a > 12 ? (a, b) : (b, a);
  if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  return DateTime(y, mo, d);
}

int? _intFrom(String raw) => raw.isEmpty ? null : int.tryParse(raw);

double? _doubleFrom(String raw) => raw.isEmpty ? null : double.tryParse(raw);

/// What a CSV would add if it were imported.
typedef CsvPreview = ({int roundsAdded, int roundsSkipped, int coursesAdded});

/// What a CSV import actually did.
///
/// [roundIds] is what makes the import undoable: the store has no way to tell
/// an imported round from a posted one afterwards, so the ids are captured
/// while the rows being added are still the ones in the loop.
typedef CsvImportResult = ({
  int added,
  int skipped,
  int coursesAdded,
  List<String> roundIds,
});

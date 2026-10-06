/// Builds backup files of the posted rounds.
///
/// Kept free of Flutter and plugins so the output can be asserted on
/// directly in tests: the exact bytes a user ends up with must not depend on
/// a widget tree or a file dialog.
///
/// Two formats, because a backup has two jobs. [toCsv] is for reading and
/// re-checking a history in a spreadsheet. [toJson] is a faithful copy of
/// everything the app stores, so a backup can also be restored later — it
/// keeps the custom courses and the score colors that a rounds-only file
/// would drop.
library;

import 'dart:convert';

import 'models.dart';

/// Quoted CSV field.
///
/// Only quotes when it has to, so a plain numeric column stays readable in a
/// text editor instead of arriving as `75`.
String _csvField(Object? v) {
  final s = v?.toString() ?? '';
  if (s.contains(RegExp('[",\n\r]'))) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

String _csvRow(List<Object?> cells) => cells.map(_csvField).join(',');

/// Two-decimal fixed formatting, so a differential reads as 8.40 and not
/// 8.4 — the sort and the eyeball both want a stable width.
String _d(double v) => v.toStringAsFixed(2);

/// Header row for [toCsv]. Exposed so a caller can document the columns.
const csvHeader = <String>[
  'id',
  'played_at',
  'course',
  'tee',
  'holes',
  'start_hole',
  'par',
  'gross',
  'to_par',
  'course_handicap',
  'index_at_play',
  'rating',
  'slope',
  'differential',
  'adjusted_gross',
  'putts',
  'penalties',
  'scores',
];

/// The whole posted history as CSV, newest round last.
///
/// One row per round. Course and tee are resolved to their names so the file
/// stays readable if the app's ids ever change; a round whose course was
/// deleted keeps a '?' rather than dropping the row, because a backup that
/// quietly loses rounds is worse than one with a hole in it.
///
/// [differentialFor] supplies the handicap differential, which needs the tee
/// to compute. Where it is unavailable the column is left empty rather than
/// filled with a guess: a wrong differential would look authoritative in a
/// spreadsheet, and this file exists to be trusted.
String toCsv(
  List<Round> rounds, {
  required Course? Function(String courseId) courseById,
  required Tee? Function(String courseId, String teeId) teeById,
  double? Function(Round round, Tee tee)? differentialFor,
  int? Function(Round round, Tee tee)? adjustedGrossFor,
  int? Function(Round round)? puttsFor,
  int? Function(Round round)? penaltiesFor,
}) {
  final b = StringBuffer()..writeln(csvHeader.join(','));
  final sorted = [...rounds]..sort((a, b) => a.playedAt.compareTo(b.playedAt));
  for (final r in sorted) {
    final course = courseById(r.courseId);
    final tee = teeById(r.courseId, r.teeId);
    // Null when the tee no longer covers the round, which is a different
    // thing from a par of 0: the to-par column is left blank rather than
    // reporting a number the app itself cannot vouch for.
    final pars = tee == null ? null : r.parsOn(tee);
    final par = pars?.fold(0, (a, p) => a + p);
    final gross = r.totalGross;
    b.writeln(
      _csvRow([
        r.id,
        r.playedAt.toIso8601String(),
        course?.name ?? '?',
        tee?.name ?? '?',
        r.holes.length,
        r.startHole + 1,
        par ?? '',
        gross,
        par == null ? '' : _signed(gross - par),
        r.courseHandicap,
        _optD(r.handicapIndexAtPlay),
        tee?.rating.toStringAsFixed(1) ?? '',
        tee?.slope ?? '',
        // Only meaningful for an 18-hole round on an 18-hole tee.
        tee != null && differentialFor != null
            ? _optD(differentialFor(r, tee))
            : '',
        tee != null && adjustedGrossFor != null
            ? (adjustedGrossFor(r, tee) ?? '')
            : '',
        puttsFor?.call(r) ?? '',
        penaltiesFor?.call(r) ?? '',
        // Scores as one cell so a spreadsheet keeps the round together.
        r.holes.map((h) => h.score).join(' '),
      ]),
    );
  }
  return b.toString();
}

String _signed(int v) => v > 0 ? '+$v' : '$v';

/// Formats a possibly-absent figure, leaving it blank rather than writing 0.
String _optD(double? v) => v == null ? '' : _d(v);

/// A complete backup of the app as JSON.
///
/// "Everything" means everything the app holds, so this carries more than the
/// save file does:
///
/// * **Every course**, not only the custom ones. The bundled courses are
///   recreated by the app, but a backup that omits them is not a snapshot —
///   and if a course is later re-parsed or retuned, the file no longer
///   describes what the user actually had.
/// * **Score colours**, the only user setting the app stores.
/// * **Course and round photos**, inline as base64. They live in the app's
///   private storage and are referenced by path, so without the bytes a
///   restored course or round comes back with a dangling image reference.
///
/// The save file deliberately keeps a smaller payload: it is rewritten on
/// every mutation, and embedding megabytes of base64 on each posted round
/// would be ruinous. This runs only when the user asks for a backup.
String toJson(
  List<Round> rounds,
  List<Course> courses, {
  int exportVersion = 1,
  Map<int, int> scoreColors = const {},
  String? themeMode,
  Map<String, String> photos = const {},
  String? appVersion,
}) {
  return jsonEncode({
    'exportVersion': exportVersion,
    'exportedAt': DateTime.now().toUtc().toIso8601String(),
    'appVersion': appVersion ?? '',
    // A display preference, but it is part of what the app stores, and the
    // save file and the backup are written by different code: anything in one
    // and not the other is state that a restore would quietly drop.
    'themeMode': themeMode ?? '',
    'rounds': [for (final r in rounds) r.toJson()],
    'courses': [for (final c in courses) c.toJson()],
    'scoreColors': {for (final e in scoreColors.entries) '${e.key}': e.value},
    // Keyed by file name so the bytes can be written back to the same place
    // the course's or round's imagePath points at.
    'photos': photos,
  });
}

/// Key the inline course photos are stored under.
String photoKey(Course course) => '${course.id}.jpg';

/// Key the inline round photos are stored under. The prefix keeps them
/// disjoint from course keys, since round and course ids share no namespace.
String roundPhotoKey(Round round) => 'round-${round.id}.jpg';

/// A backup read back off disk, not yet merged into anything.
class Backup {
  final List<Round> rounds;
  final List<Course> courses;

  /// Null when the file carried no colors, which is how an older backup or a
  /// hand-edited file says "leave the current colors alone" rather than
  /// "reset them to nothing".
  final Map<int, int>? scoreColors;
  final int? exportVersion;
  final DateTime? exportedAt;
  final String? appVersion;

  /// The brightness preference, when the file names one. Null when absent or
  /// unrecognised, which the importer reads as "leave the setting alone".
  final String? themeMode;

  /// Inline course and round photos, base64, keyed by file name.
  final Map<String, String> photos;

  const Backup({
    required this.rounds,
    required this.courses,
    this.scoreColors,
    this.exportVersion,
    this.exportedAt,
    this.appVersion,
    this.themeMode,
    this.photos = const {},
  });
}

/// Thrown when a file cannot be read as a backup.
///
/// The message is shown to the user, so it says what is wrong rather than
/// what went wrong internally.
class BackupFormatException implements Exception {
  final String message;
  BackupFormatException(this.message);
  @override
  String toString() => message;
}

/// Reads a backup written by [toJson].
///
/// Nothing here mutates the store: the whole document is decoded and checked
/// before the caller is handed a [Backup]. A file that is truncated, is some
/// other JSON entirely, or holds one broken round therefore changes nothing
/// at all, rather than leaving the history half-imported.
///
/// Throws [BackupFormatException] with a message fit to show a user.
Backup parseBackup(String text) {
  Object? decoded;
  try {
    decoded = jsonDecode(text);
  } catch (_) {
    throw BackupFormatException('That file is not valid JSON.');
  }
  if (decoded is! Map) {
    throw BackupFormatException('That file is not a ghin-golf backup.');
  }
  final j = Map<String, dynamic>.from(decoded);
  // A backup has rounds. A file that merely happens to be JSON does not, and
  // accepting it would import an empty history and look like it worked.
  if (j['rounds'] is! List) {
    throw BackupFormatException(
      'That file has no rounds in it, so it is not a backup.',
    );
  }
  final rawRounds = j['rounds'] as List;
  final rounds = <Round>[];
  for (var i = 0; i < rawRounds.length; i++) {
    final e = rawRounds[i];
    if (e is! Map) {
      throw BackupFormatException('Round ${i + 1} in the file is unreadable.');
    }
    try {
      rounds.add(Round.fromJson(Map<String, dynamic>.from(e)));
    } catch (err) {
      // Say which round, because a file with one bad entry should not read
      // as a blanket "this file is broken".
      throw BackupFormatException('Round ${i + 1} in the file is unreadable.');
    }
  }
  final courses = <Course>[];
  // Backups written before the full snapshot used the key customCourses, and
  // an older file should still open rather than coming back empty.
  final rawCourses = j['courses'] ?? j['customCourses'];
  if (rawCourses is List) {
    for (var i = 0; i < rawCourses.length; i++) {
      final e = rawCourses[i];
      if (e is! Map) {
        continue; // a bad course is survivable: rounds still import
      }
      try {
        courses.add(Course.fromJson(Map<String, dynamic>.from(e)));
      } catch (_) {}
    }
  }
  final rawColors = j['scoreColors'];
  Map<int, int>? colors;
  if (rawColors is Map) {
    colors = <int, int>{};
    for (final e in rawColors.entries) {
      final d = int.tryParse('${e.key}');
      final v = e.value is num ? (e.value as num).toInt() : null;
      if (d == null || v == null) continue; // skip, do not fail the import
      colors[d] = v;
    }
  }
  final photos = <String, String>{};
  final rawPhotos = j['photos'];
  if (rawPhotos is Map) {
    for (final e in rawPhotos.entries) {
      final v = e.value;
      // Only well-formed base64 is kept, so a truncated photo cannot be
      // written out as a corrupt image that then fails to load.
      if (v is! String || v.isEmpty) continue;
      if (!RegExp(r'^[A-Za-z0-9+/]+={0,2}$').hasMatch(v)) continue;
      photos['${e.key}'] = v;
    }
  }
  final version = (j['exportVersion'] as num?)?.toInt();
  DateTime? exportedAt;
  final rawAt = j['exportedAt'];
  if (rawAt is String) {
    exportedAt = DateTime.tryParse(rawAt);
  }
  return Backup(
    rounds: rounds,
    courses: courses,
    scoreColors: colors,
    exportVersion: version,
    exportedAt: exportedAt,
    appVersion: j['appVersion'] is String ? j['appVersion'] as String : null,
    themeMode: switch (j['themeMode']) {
      final String v when v.isNotEmpty => v,
      _ => null,
    },
    photos: photos,
  );
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;

import 'data.dart';
import 'csv_import.dart';
import 'export.dart';
import 'models.dart';
import 'scan_service.dart' show scorecardPhotoDirectory;
import 'whs.dart';

/// Stamped into every backup, so a file found on an old phone or a new one can
/// be identified. Kept as a literal rather than read from the platform so
/// tests and the desktop build get the same value as the app.
const appVersion = '1.0.0+1';

/// What a restore would change, counted the same way the restore counts it.
typedef BackupPreview = ({
  int roundsAdded,
  int roundsSkipped,
  int coursesAdded,
  int colorsChanged,
  int photosRestored,
  bool themeChanged,
});

/// Local-first store. Persists to a JSON file with no plugins:
/// Linux/desktop -> $HOME/.ghin-golf.json, Android -> temp dir fallback.
class GolfStore extends ChangeNotifier {
  final String? _filePath;

  GolfStore({String? filePath}) : _filePath = filePath;

  List<Course> courses = seedCourses();
  List<Round> rounds = [];

  /// Score-vs-par colors as ARGB ints, keyed by clamped diff
  /// (-2 eagle-or-better … 3 triple-or-worse). User-editable, persisted.
  Map<int, int> scoreColors = Map.of(defaultScoreColors);

  /// Stamped into every backup so a file found on an old phone can be
  /// identified. Kept as a plain field rather than read from the platform so
  /// tests and the desktop build can set it.
  String appVersion = '';

  /// Light, dark, or follow the system. A preference rather than a device
  /// setting because a golfer checking a scorecard on a bright green in the
  /// sun wants light, and the same golfer at 9pm wants dark, from one app.
  ///
  /// Stored as a [ThemeMode] but persisted as its name, so the save file stays
  /// readable and an unknown value from a newer build falls back rather than
  /// failing to load.
  ThemeMode _themeMode = ThemeMode.system;

  /// Read-only on purpose: [setThemeMode] is the only way to change it, so
  /// every write goes through the save and the repaint.
  ThemeMode get themeMode => _themeMode;

  /// The save-file spelling of [themeMode]. For [load] and tests.
  String get themeModeName => _themeMode.name;

  set themeModeName(String? v) {
    _themeMode = ThemeMode.values.firstWhere(
      (m) => m.name == v,
      // Anything unrecognised — a file from a future build, a hand edit —
      // resolves to following the system, which is what the app did before
      // this preference existed.
      orElse: () => ThemeMode.system,
    );
  }

  /// The posted history as CSV, for export.
  ///
  /// Lives here rather than in the UI so it uses the same lookups as the
  /// handicap math: a round whose tee no longer resolves gets a blank
  /// differential instead of a number the rest of the app would not produce.
  String exportRoundsCsv() => toCsv(
    rounds,
    courseById: courseById,
    teeById: teeById,
    differentialFor: (r, tee) => r.differential(tee),
    adjustedGrossFor: (r, tee) => r.adjustedGrossFor(tee),
    puttsFor: (r) => r.totalPutts,
    penaltiesFor: (r) => r.totalPenalties,
  );

  /// A restorable backup of everything: every round, every course, the score
  /// colors, and the course photos.
  ///
  /// Differs from the save file by carrying a version and a timestamp, and by
  /// holding all courses rather than only the custom ones, so a backup stays a
  /// true snapshot even if the app's own data changes underneath it.
  String exportRoundsJson() => toJson(
    rounds,
    courses,
    scoreColors: scoreColors,
    photos: _collectPhotos(),
    appVersion: appVersion,
    themeMode: themeModeName,
  );

  /// The course photos, base64, keyed the way [photoKey] names them.
  ///
  /// Reads from the paths the courses actually hold, so a photo moved or
  /// deleted on disk simply does not appear rather than breaking the export.
  /// Skipped on web, where imagePath is a blob url and there is no file to
  /// read.
  Map<String, String> _collectPhotos() {
    final out = <String, String>{};
    if (kIsWeb) return out;
    for (final c in courses) {
      final path = c.imagePath;
      if (path.isEmpty) continue;
      try {
        final f = File(path);
        if (!f.existsSync()) continue;
        out[photoKey(c)] = base64Encode(f.readAsBytesSync());
      } catch (_) {
        // A photo that cannot be read costs an image, not the backup.
      }
    }
    return out;
  }

  /// Merges a parsed backup into the store and saves once.
  ///
  /// Merging rather than replacing is the whole point: the round being
  /// restored onto is the very one at risk in the backup, so a restore that
  /// could clear the current history would be a poor way to recover it. Ids
  /// already present are skipped, which also makes a second import of the same
  /// file a no-op instead of a set of duplicates.
  ///
  /// Course photos are written to disk and the restored courses repointed at
  /// them, because a course whose bytes are in the backup but not on the disk
  /// would still come back showing a broken image.
  ///
  /// Returns what changed, so the caller can report it rather than implying
  /// the whole file was new.
  Future<({int added, int skipped, int coursesAdded, int photosRestored})>
  importBackup(Backup b) async {
    final known = {for (final r in rounds) r.id};
    final knownCourses = {for (final c in courses) c.id};
    var added = 0, skipped = 0, coursesAdded = 0;
    for (final r in b.rounds) {
      if (known.contains(r.id)) {
        skipped++;
        continue;
      }
      rounds.add(r);
      known.add(r.id);
      added++;
    }
    for (final c in b.courses) {
      // A course id the app already has is left alone: the bundled seed
      // courses share ids with whatever the user edited, and their edited
      // pars are the ones the existing rounds were scored against.
      if (knownCourses.contains(c.id)) continue;
      courses.add(c);
      knownCourses.add(c.id);
      coursesAdded++;
    }
    final photosRestored = await _restorePhotos(b);
    if (b.scoreColors != null && b.scoreColors!.isNotEmpty) {
      scoreColors = {...scoreColors, ...b.scoreColors!};
    }
    // Applied after the data, and only when the file actually names a mode, so
    // an older backup leaves the phone's current setting alone.
    if (b.themeMode != null) themeModeName = b.themeMode;
    save();
    notifyListeners();
    return (
      added: added,
      skipped: skipped,
      coursesAdded: coursesAdded,
      photosRestored: photosRestored,
    );
  }

  /// A course whose name matches, ignoring case and stray whitespace.
  ///
  /// Matching on name is the only way a CSV can be tied to a course: the ids
  /// in a spreadsheet either came from a different install, or from a
  /// different app entirely.
  Course? courseByName(String name) {
    final key = _nameKey(name);
    for (final c in courses) {
      if (_nameKey(c.name) == key) return c;
    }
    return null;
  }

  Tee? teeByName(Course course, String name) {
    final key = _nameKey(name);
    for (final t in course.tees) {
      if (_nameKey(t.name) == key) return t;
    }
    return null;
  }

  static String _nameKey(String v) =>
      v.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// What [importCsv] would bring in.
  ///
  /// Resolves every row exactly the way the import does, without touching the
  /// store, so the count the user confirms is the count they get.
  CsvPreview previewCsv(List<CsvRound> rows) {
    final existing = _existingRoundKeys();
    final planned = <String>{};
    // Counted per *course*, not per row. Two rounds off the same unrecognised
    // course build one course, and a preview that said otherwise would be
    // promising the user more than the import delivers.
    final plannedCourses = <String>{};
    var added = 0, skipped = 0, coursesAdded = 0;
    for (final row in rows) {
      final key = _csvKey(row);
      if (existing.contains(key) || planned.contains(key)) {
        skipped++;
        continue;
      }
      planned.add(key);
      added++;
      final course = _courseForCsv(row);
      if (course != null) continue;
      final id = _csvCourseId(row);
      if (plannedCourses.add(id)) coursesAdded++;
    }
    return (
      roundsAdded: added,
      roundsSkipped: skipped,
      coursesAdded: coursesAdded,
    );
  }

  /// Restores rounds from a parsed CSV.
  ///
  /// Matches wherever it can: a round naming a course the app already has is
  /// posted against that course, so its real pars and stroke indexes apply and
  /// the differential is the one the app would have computed at the time.
  /// Only a course the app has never heard of gets reconstructed, and the
  /// caller reports how many, because a reconstructed course is a stand-in.
  CsvImportResult importCsv(List<CsvRound> rows) {
    final existing = _existingRoundKeys();
    final planned = <String>{};
    final addedIds = <String>[];
    var added = 0, skipped = 0, coursesAdded = 0;
    for (final row in rows) {
      final key = _csvKey(row);
      if (existing.contains(key) || planned.contains(key)) {
        skipped++;
        continue;
      }
      planned.add(key);

      var course = _courseForCsv(row);
      var reconstructed = false;
      if (course == null) {
        course = _courseFromCsv(row);
        courses.add(course);
        coursesAdded++;
        reconstructed = true;
      }
      final tee = reconstructed
          ? course.tees.first
          : teeByName(course, row.teeName) ?? _addCsvTee(course, row);
      final round = row.toRound(courseId: course.id, teeId: tee.id);
      rounds.add(round);
      addedIds.add(round.id);
      added++;
    }
    if (added > 0) {
      save();
      notifyListeners();
    }
    return (
      added: added,
      skipped: skipped,
      coursesAdded: coursesAdded,
      roundIds: addedIds,
    );
  }

  /// The course a row belongs to, or null if the app has never seen it.
  ///
  /// Name matching is enough on its own, and deliberately so: a course built
  /// for row one carries row one's name, so row two of the same course finds
  /// it here. A second lookup keyed on the generated id would be a branch
  /// nothing can reach.
  Course? _courseForCsv(CsvRound row) =>
      row.courseName.isEmpty ? null : courseByName(row.courseName);

  /// The id a row's course would be built under, derived from its name so the
  /// same course always lands on the same id and a second import finds the
  /// first one's work instead of building a duplicate.
  String _csvCourseId(CsvRound row) =>
      'csv-course-${_slug(row.courseName.isEmpty ? 'Unknown' : row.courseName)}';

  /// A course built to hold a round the app has never seen.
  ///
  /// A CSV routinely names courses that are not in the app, and refusing the
  /// file over it would make the import useless for its main case: moving a
  /// history in from somewhere else.
  ///
  /// Per-hole par is **distributed** from the row's own par total, because a
  /// spreadsheet carries a total and not a hole-by-hole layout. That is a
  /// reconstruction, not a recovery, so the course is marked custom and the
  /// caller says out loud how many were made this way.
  Course _courseFromCsv(CsvRound row) {
    final n = row.scores.length;
    final holes = _parPerHole(row, n);
    final id = _csvCourseId(row);
    return Course(
      id: id,
      name: row.courseName.isEmpty ? 'Unknown course' : row.courseName,
      city: '',
      state: '',
      custom: true,
      tees: [
        Tee(
          id: '$id-tee',
          name: row.teeName.isEmpty ? 'Imported' : row.teeName,
          rating: row.rating ?? 0,
          slope: row.slope ?? 0,
          holes: [
            for (var i = 0; i < n; i++)
              HoleInfo(
                number: row.startHole + i + 1,
                par: holes[i],
                yardage: 0,
                strokeIndex: i + 1,
              ),
          ],
        ),
      ],
    );
  }

  /// Spreads the row's par total across the holes played, or falls back to all
  /// par 4 when the file has no par column — the most common hole, and so the
  /// least wrong flat guess available.
  List<int> _parPerHole(CsvRound row, int n) {
    if (n == 0) return const [];
    final total = row.parTotal;
    if (total == null || total <= 0) return List.filled(n, 4);
    final base = total ~/ n;
    final extra = total % n;
    return [for (var i = 0; i < n; i++) base + (i < extra ? 1 : 0)];
  }

  /// Adds the row's tee to a course that exists but does not have it, so a
  /// round played off the Gold tees is not scored against the White.
  Tee _addCsvTee(Course course, CsvRound row) {
    final n = row.scores.length;
    final tee = Tee(
      id: '${course.id}-csv-${_slug(row.teeName.isEmpty ? 'imported' : row.teeName)}',
      name: row.teeName.isEmpty ? 'Imported' : row.teeName,
      rating: row.rating ?? 0,
      slope: row.slope ?? 0,
      holes: [
        for (var i = 0; i < n; i++)
          HoleInfo(
            number: row.startHole + i + 1,
            // No total par for a tee invented from a row, so every hole is a 4.
            par: 4,
            yardage: 0,
            strokeIndex: i + 1,
          ),
      ],
    );
    courses[courses.indexWhere((c) => c.id == course.id)] = course.withTee(tee);
    return tee;
  }

  /// Identity of a round for spotting a re-import.
  ///
  /// Deliberately the *content* — course, tee, date, and the scores — and not
  /// the file's id. A round that arrives twice under different ids is still
  /// the same round, and posting it twice would corrupt the handicap average
  /// in a way nothing in the UI would reveal.
  String _csvKey(CsvRound row) =>
      _csvKeyOf(row.courseName, row.teeName, row.playedAt, row.scores);

  static String _csvKeyOf(
    String courseName,
    String teeName,
    DateTime playedAt,
    List<int> scores,
  ) =>
      '$courseName|$teeName|${playedAt.toIso8601String()}|'
      '${scores.join(',')}';

  /// The same keys, built from the rounds already posted.
  ///
  /// Falls back to the raw id when a course or tee has since been deleted, so
  /// the key stays unique rather than collapsing two rounds into one.
  Set<String> _existingRoundKeys() {
    final out = <String>{};
    for (final r in rounds) {
      final c = courseById(r.courseId);
      final t = teeById(r.courseId, r.teeId);
      out.add(
        _csvKeyOf(c?.name ?? r.courseId, t?.name ?? r.teeId, r.playedAt, [
          for (final h in r.holes) h.score,
        ]),
      );
    }
    return out;
  }

  static String _slug(String v) => v
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  /// Writes the backup's inline photos to the same folder the scanner uses and
  /// repoints the courses at them. Best effort: a photo that will not write
  /// costs an image, not the restore.
  Future<int> _restorePhotos(Backup b) async {
    if (b.photos.isEmpty || kIsWeb) return 0;
    var written = 0;
    Directory? dir;
    for (final entry in b.photos.entries) {
      try {
        // Only photos the app would actually gain. A key with no course is an
        // orphan from a course that was never restored, and a course that
        // already has its photo on disk has nothing to gain either.
        final idx = courses.indexWhere((c) => photoKey(c) == entry.key);
        if (idx < 0) continue;
        final existing = courses[idx].imagePath;
        if (existing.isNotEmpty && _fileExists(existing)) continue;
        dir ??= await scorecardPhotoDirectory();
        final bytes = base64Decode(entry.value);
        final dest = '${dir.path}/${entry.key}';
        await File(dest).writeAsBytes(bytes, flush: true);
        courses[idx] = courses[idx].copyWithImagePath(dest);
        written++;
      } catch (_) {
        // Keep going: one bad photo should not abandon the rest.
      }
    }
    return written;
  }

  static bool _fileExists(String path) {
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// What [importBackup] would change, using the same rules it uses.
  ///
  /// The restore screen asks "is there anything here?" before it commits, and
  /// that question has to be asked of the whole backup. An earlier version
  /// looked only at rounds, so a backup whose rounds were all already present
  /// was reported as "nothing new" and the courses, colors and photos it
  /// carried were silently dropped. Deriving the preview from the same rules as
  /// the import keeps the number the user is shown from disagreeing with what
  /// actually happens.
  BackupPreview previewBackup(Backup b) {
    final knownRounds = {for (final r in rounds) r.id};
    final knownCourses = {for (final c in courses) c.id};
    var roundsAdded = 0, roundsSkipped = 0;
    for (final r in b.rounds) {
      if (knownRounds.contains(r.id)) {
        roundsSkipped++;
      } else {
        roundsAdded++;
      }
    }
    var coursesAdded = 0;
    for (final c in b.courses) {
      if (!knownCourses.contains(c.id)) coursesAdded++;
    }
    // The import adds the backup's courses before it restores photos, so a
    // photo for a course this backup is about to add still counts. Matching
    // against the courses already in the store would undercount exactly the
    // case a fresh restore is for.
    final effective = <Course>[
      ...courses,
      for (final c in b.courses)
        if (!knownCourses.contains(c.id)) c,
    ];
    // Appearance restores from a backup too, so a backup that carries nothing
    // but a different theme is still worth restoring. Counted the same way as
    // the colors: a differing value is a change, not merely a present key.
    final themeChanged = b.themeMode != null && b.themeMode != themeModeName;

    // The import lets the backup's colors win, so a color is a change when the
    // value differs, not merely when the key is absent.
    var colorsChanged = 0;
    final incoming = b.scoreColors;
    if (incoming != null) {
      for (final e in incoming.entries) {
        if (scoreColors[e.key] != e.value) colorsChanged++;
      }
    }
    var photosRestored = 0;
    if (!kIsWeb) {
      for (final key in b.photos.keys) {
        final idx = effective.indexWhere((c) => photoKey(c) == key);
        if (idx < 0) continue;
        final existing = effective[idx].imagePath;
        if (existing.isEmpty || !_fileExists(existing)) photosRestored++;
      }
    }
    return (
      roundsAdded: roundsAdded,
      roundsSkipped: roundsSkipped,
      coursesAdded: coursesAdded,
      colorsChanged: colorsChanged,
      photosRestored: photosRestored,
      themeChanged: themeChanged,
    );
  }

  /// Saved color for a score diff (clamped to -2..3), or the default.
  int scoreColorValue(int diff) {
    final d = diff.clamp(-2, 3);
    return scoreColors[d] ?? defaultScoreColors[d]!;
  }

  /// Sets the app's brightness and persists it.
  ///
  /// A method rather than a bare field write so no caller has to remember the
  /// save-then-notify order, and neither half can be forgotten: a theme that
  /// looks right until the app restarts is worse than one that never changes.
  void setThemeMode(ThemeMode mode) {
    if (mode == _themeMode) return;
    _themeMode = mode;
    save();
    notifyListeners();
  }

  void setScoreColor(int diff, int value) {
    scoreColors[diff.clamp(-2, 3)] = value;
    save();
    notifyListeners();
  }

  void resetScoreColors() {
    scoreColors = Map.of(defaultScoreColors);
    save();
    notifyListeners();
  }

  /// The player's Handicap Index, or null before three acceptable scores.
  ///
  /// Built from the whole scoring record rather than from a bag of
  /// differentials, because the WHS cap depends on the record's length and
  /// age. Rounds whose course or tee no longer resolves are dropped: their
  /// handicap is unknown, and inventing one would quietly move the index.
  double? get handicapIndex {
    return _handicapIndexFor(rounds);
  }

  /// Index in effect before any score on [date] is posted.
  ///
  /// The handicap revision happens after the day is complete, so a second
  /// round played on the same calendar date uses the same index as the first.
  double? handicapIndexBefore(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return _handicapIndexFor(
      rounds.where((round) {
        final playedDay = DateTime(
          round.playedAt.year,
          round.playedAt.month,
          round.playedAt.day,
        );
        return playedDay.isBefore(day);
      }),
    );
  }

  double? _handicapIndexFor(Iterable<Round> source) {
    final record = <ScoredRound>[];
    for (final r in source) {
      final tee = teeById(r.courseId, r.teeId);
      if (tee == null) continue;
      final d = r.differential(tee);
      if (d != null) {
        final raw = r.unroundedDifferential(tee);
        record.add(
          ScoredRound(
            playedAt: r.playedAt,
            differential: d,
            unroundedDifferential: raw,
            handicapIndexAtPlay: r.handicapIndexAtPlay,
          ),
        );
      }
    }
    if (record.isEmpty) return null;
    return handicapIndexFunc(record);
  }

  Course? courseById(String id) {
    for (final c in courses) {
      if (c.id == id) return c;
    }
    return null;
  }

  Tee? teeById(String courseId, String teeId) {
    final c = courseById(courseId);
    if (c == null) return null;
    for (final t in c.tees) {
      if (t.id == teeId) return t;
    }
    return null;
  }

  /// Token search over name + city + state. Every token must match somewhere.
  List<Course> searchCourses(String query) {
    final tokens = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return List<Course>.from(courses);
    return courses.where((c) {
      final hay = '${c.name} ${c.city} ${c.state}'.toLowerCase();
      return tokens.every((t) => hay.contains(t));
    }).toList();
  }

  void addCourse(Course c) {
    courses.add(c);
    save();
    notifyListeners();
  }

  /// Deletes a course. Rounds already posted on it are kept; their
  /// course name renders as '?' and they are skipped by stat summaries.
  void deleteCourse(String id) {
    courses.removeWhere((c) => c.id == id);
    save();
    notifyListeners();
  }

  /// Replaces a saved custom course (same id). Posted rounds stay linked.
  void updateCourse(Course c) {
    final i = courses.indexWhere((e) => e.id == c.id);
    if (i < 0) return;
    courses[i] = c;
    save();
    notifyListeners();
  }

  void addRound(Round r) {
    rounds.add(r);
    save();
    notifyListeners();
  }

  /// Replaces the round with the same id, keeping its position.
  ///
  /// Editing a posted round has to update the original rather than post a
  /// second one: the round being corrected is the one in the history, and a
  /// duplicate would double it in the handicap average.
  void updateRound(Round r) {
    final i = rounds.indexWhere((x) => x.id == r.id);
    if (i < 0) {
      addRound(r);
      return;
    }
    rounds[i] = r;
    save();
    notifyListeners();
  }

  /// Removes a round and hands back what was removed and where it sat, so an
  /// undo can put it back in the same spot rather than at the end of a list
  /// whose order the stats and exports depend on.
  ({Round round, int index})? deleteRound(String id) {
    final i = rounds.indexWhere((r) => r.id == id);
    if (i < 0) return null;
    final removed = rounds.removeAt(i);
    save();
    notifyListeners();
    return (round: removed, index: i);
  }

  /// Removes several rounds at once, in one write.
  ///
  /// Backs a CSV import's undo, and takes ids rather than a count: a round
  /// posted after the import is not the one that should disappear, and nothing
  /// in the store's ordering could tell the two apart after the fact.
  ///
  /// One pass on purpose. Undoing by deleting each round in turn rewrites the
  /// save file once per round, and deleting from the end backwards is what
  /// keeps the survivors in the order the stats and exports depend on — this
  /// simply never reorders them.
  int removeRounds(List<String> ids) {
    final drop = ids.toSet();
    if (drop.isEmpty) return 0;
    final kept = rounds.where((r) => !drop.contains(r.id)).toList();
    final removed = rounds.length - kept.length;
    if (removed == 0) return 0;
    rounds = kept;
    save();
    notifyListeners();
    return removed;
  }

  /// Puts a deleted round back where it was.
  void restoreRound(Round r, int index) {
    final at = index.clamp(0, rounds.length);
    rounds.insert(at, r);
    save();
    notifyListeners();
  }

  // ---- stats over 18-hole rounds ----
  /// Round-level averages, over the rounds that can still be read.
  ///
  /// A round whose course or tee has been deleted is skipped entirely, so it
  /// must also be left out of the per-round denominators — counting it there
  /// would drag the average down with holes that were never measured.
  ///
  /// Holes are read from [Round.startHole] on, not from the front of the tee:
  /// a back-nine round's scores belong to holes 10-18, and pairing them with
  /// the front nine would grade every hole against the wrong par.
  Map<String, double> statSummary() {
    var fwHit = 0, fwTotal = 0, girHit = 0, holes = 0, putts = 0, pens = 0;
    var driveTotal = 0, driveCount = 0, scoredRounds = 0;
    for (final r in rounds) {
      final tee = teeById(r.courseId, r.teeId);
      if (tee == null) continue;
      // A tee edited down after the round no longer covers the holes played.
      if (r.startHole + r.holes.length > tee.holes.length) continue;
      scoredRounds++;
      for (var i = 0; i < r.holes.length; i++) {
        final h = r.holes[i];
        final t = tee.holes[r.startHole + i];
        holes++;
        putts += h.putts;
        pens += h.penalties;
        if (t.par > 3) {
          if (h.fairway != 'NA') {
            fwTotal++;
            if (h.fairway == 'H') fwHit++;
          }
        }
        if (h.gir) girHit++;
        if (h.driveDistance > 0) {
          driveTotal += h.driveDistance;
          driveCount++;
        }
      }
    }
    if (holes == 0) return {};
    return {
      'FIR': fwTotal == 0 ? 0 : fwHit * 100.0 / fwTotal,
      'GIR': girHit * 100.0 / holes,
      'Putts/Hole': putts * 1.0 / holes,
      'Pen/Round': scoredRounds == 0 ? 0 : pens * 1.0 / scoredRounds,
      'AvgDrive': driveCount == 0 ? 0 : driveTotal * 1.0 / driveCount,
    };
  }

  // ---- persistence ----
  /// Test-only override for the backing file, so tests never touch the
  /// user's real data.
  @visibleForTesting
  static String? testFilePath;

  /// Tail of the write chain, so saves queue instead of overlapping.
  Future<void> _pending = Future<void>.value();

  File _file() {
    final instancePath = _filePath;
    if (instancePath != null) return File(instancePath);
    final t = testFilePath;
    if (t != null) return File(t);
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home != null && home.isNotEmpty) {
      return File('$home/.ghin-golf.json');
    }
    return File('${Directory.systemTemp.path}/ghin-golf.json');
  }

  Future<void> load() async {
    try {
      final f = _file();
      if (!await f.exists()) return;
      final j = json.decode(await f.readAsString()) as Map<String, dynamic>;
      rounds = ((j['rounds'] as List?) ?? [])
          .map((e) => Round.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      final customs = ((j['customCourses'] as List?) ?? [])
          .map((e) => Course.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      courses = [...seedCourses(), ...customs];
      scoreColors = decodeScoreColors(j['scoreColors']);
      themeModeName = j['themeMode'] as String?;
      notifyListeners();
    } catch (_) {
      // Unreadable file: keep the evidence before anything overwrites it, so
      // a bad write can be recovered by hand instead of silently starting the
      // user off with an empty history.
      _quarantineUnreadable();
    }
  }

  /// Moves an unparseable save file aside, timestamped so the copy says when
  /// the bad write happened. Never throws.
  void _quarantineUnreadable() {
    try {
      final f = _file();
      if (!f.existsSync()) return;
      final now = DateTime.now();
      final stamp =
          '${now.year}${_pad2(now.month)}${_pad2(now.day)}'
          '-${_pad2(now.hour)}${_pad2(now.minute)}${_pad2(now.second)}';
      f.copySync('${f.path}.corrupt-$stamp');
    } catch (_) {}
  }

  static String _pad2(int n) => n.toString().padLeft(2, '0');

  /// Saves the whole store.
  ///
  /// Called on every mutation, and none of them wait for the last, so
  /// several writes are normally in flight at once. They are chained: each
  /// one starts after the previous has finished, so the file is only ever
  /// written by one writer and the last queued state is the one that lands.
  ///
  /// The chain never breaks, so a write that fails does not wedge the rest.
  Future<void> save() {
    _pending = _pending.then((_) => _writeToDisk()).catchError((_) {});
    return _pending;
  }

  Future<void> _writeToDisk() async {
    try {
      final f = _file();
      final payload = json.encode({
        'rounds': rounds.map((r) => r.toJson()).toList(),
        'customCourses': courses
            .where((c) => c.custom)
            .map((c) => c.toJson())
            .toList(),
        'scoreColors': encodeScoreColors(scoreColors),
        // A display preference, not history: deliberately not in the JSON
        // backup, which is about getting your rounds back, not about how this
        // particular phone was set up.
        'themeMode': themeMode.name,
      });
      // Write beside the target, then rename over it. A rename within a
      // directory is atomic, so the save file holds either the old contents
      // or the new ones and is never a truncated mixture — which is the
      // difference between losing the round being posted and losing every
      // round ever posted, since [load] cannot read a half-written file.
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(payload, flush: true);
      await tmp.rename(f.path);
    } catch (_) {}
  }
}

// Alias to avoid name clash between the getter and the whs function.
double? handicapIndexFunc(List<ScoredRound> record) =>
    handicapIndexFromRecord(record);

/// Default score-vs-par palette (ARGB): eagle-or-better, birdie, par,
/// bogey, double, triple-or-worse.
const Map<int, int> defaultScoreColors = {
  -2: 0xFF1B5E20,
  -1: 0xFF43A047,
  0: 0xFF607D8B,
  1: 0xFFEF6C00,
  2: 0xFFE65100,
  3: 0xFFD32F2F,
};

/// Labels for the six editable score buckets, diff first.
const List<(int, String)> scoreColorLabels = [
  (-2, 'Eagle or better'),
  (-1, 'Birdie'),
  (0, 'Par'),
  (1, 'Bogey'),
  (2, 'Double'),
  (3, 'Triple or worse'),
];

/// JSON codec for the persisted colors (keys are strings in JSON).
/// Unknown/missing entries fall back to defaults; never throws.
Map<String, int> encodeScoreColors(Map<int, int> colors) => {
  for (final e in colors.entries) '${e.key}': e.value,
};

Map<int, int> decodeScoreColors(Object? json) {
  final out = Map<int, int>.of(defaultScoreColors);
  if (json is Map) {
    for (final e in json.entries) {
      final d = int.tryParse('${e.key}');
      final v = e.value is num
          ? (e.value as num).toInt()
          : int.tryParse('${e.value}');
      if (d != null && d >= -2 && d <= 3 && v != null) out[d] = v;
    }
  }
  return out;
}

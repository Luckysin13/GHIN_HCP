import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'app_theme.dart';
import 'csv_import.dart';
import 'design_tokens.dart';
import 'ghin_brand_mark.dart';
import 'handicap_card.dart';
import 'recent_rounds_section.dart';
import 'models.dart';
import 'quick_post.dart';
import 'score_entry.dart';
import 'opengolf.dart';
import 'scan_service.dart';
import 'scorecard_scan.dart';
import 'export.dart';
import 'export_io.dart';
import 'store.dart';
import 'theme_toggle.dart';
import 'table_geometry.dart';
import 'whs.dart' as whs_engine;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = GolfStore()..appVersion = appVersion;
  await store.load();
  runApp(GhinApp(store: store));
}

class GhinApp extends StatelessWidget {
  final GolfStore store;
  const GhinApp({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => MaterialApp(
        title: 'GHIN HCP',
        theme: AppTheme.active(Brightness.light),
        darkTheme: AppTheme.active(Brightness.dark),
        themeMode: store.themeMode,
        home: RootTabs(store: store),
      ),
    );
  }
}

class RootTabs extends StatefulWidget {
  final GolfStore store;
  const RootTabs({super.key, required this.store});
  @override
  State<RootTabs> createState() => _RootTabsState();
}

class _RootTabsState extends State<RootTabs> {
  int idx = 0;
  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(store: widget.store),
      PostPage(store: widget.store),
      CoursesPage(store: widget.store),
      StatsPage(store: widget.store),
    ];
    return Scaffold(
      body: pages[idx],
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        onDestinationSelected: (i) => setState(() => idx = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.sports_golf_outlined),
            selectedIcon: Icon(Icons.sports_golf),
            label: 'Play',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map_rounded),
            label: 'Courses',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart_rounded),
            label: 'Stats',
          ),
        ],
      ),
    );
  }
}

// ---------------- HOME ----------------
class HomePage extends StatelessWidget {
  final GolfStore store;
  const HomePage({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    final hi = store.handicapIndex;
    final rounds = List<Round>.from(store.rounds)
      ..sort((a, b) => b.playedAt.compareTo(a.playedAt));
    final pending = rounds.where((r) => r.pendingSync).length;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const GhinBrandMark(key: ValueKey('ghin-brand-mark')),
            const SizedBox(width: Insets.sm),
            const Flexible(
              child: Text(
                'GHIN HCP',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        // In the app bar rather than at the foot of the page: the quick-post
        // card is tall, so a button below the recent rounds would sit off
        // screen on the first tap and a backup nobody finds is no backup.
        // Export and import sit together because they are two halves of one
        // job, and the way back in is the whole point of having a backup.
        actions: [
          ThemeModeButton(store: store),
          PopupMenuButton<String>(
            tooltip: 'Backup',
            icon: const Icon(Icons.save_alt),
            onSelected: (v) => switch (v) {
              'import' => _runImport(context, store),
              'import-csv' => _runImportCsv(context, store),
              _ => _runExport(context, store, v),
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'csv',
                child: ListTile(
                  leading: Icon(Icons.table_chart),
                  title: Text('Export CSV'),
                  subtitle: Text('One row per round, for a spreadsheet'),
                ),
              ),
              const PopupMenuItem(
                value: 'json',
                child: ListTile(
                  leading: Icon(Icons.archive),
                  title: Text('Export full backup'),
                  subtitle: Text(
                    'Everything: rounds, courses, settings, photos',
                  ),
                ),
              ),
              const PopupMenuItem(
                value: 'import',
                child: ListTile(
                  leading: Icon(Icons.restore),
                  title: Text('Import backup'),
                  subtitle: Text('Restore a JSON backup'),
                ),
              ),
              const PopupMenuItem(
                value: 'import-csv',
                child: ListTile(
                  leading: Icon(Icons.table_view),
                  title: Text('Import CSV'),
                  subtitle: Text('Bring rounds in from a spreadsheet'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(Insets.gutter),
        children: [
          HandicapCard(
            index: hi,
            roundCount: rounds.length,
            pending: pending,
            trend: TrendSpark(rounds: rounds, store: store),
          ),
          const SizedBox(height: Insets.md),
          QuickPostCard(store: store),
          const SizedBox(height: Insets.xl),
          RecentRoundsSection(
            rows: recentRows(store, rounds),
            onEdit: (r) => _editRound(context, store, r),
            onDelete: (r) => _deleteRound(context, store, r),
          ),
        ],
      ),
    );
  }
}

/// Opens a posted round for correction.
void _editRound(BuildContext context, GolfStore store, Round r) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => PostPage(store: store, existing: r),
    ),
  );
}

/// Deletes a round and offers it back, because a delete on a phone is one
/// mis-tap away from losing a round for good.
void _deleteRound(BuildContext context, GolfStore store, Round r) {
  final messenger = ScaffoldMessenger.of(context);
  final removed = store.deleteRound(r.id);
  if (removed == null) return;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        'Deleted ${courseName(store, removed.round)} • ${removed.round.totalGross}',
      ),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () => store.restoreRound(removed.round, removed.index),
      ),
    ),
  );
}

/// Backup of the posted rounds.
///
/// Two formats because they answer different needs: CSV is for reading the
/// history in a spreadsheet, JSON carries the custom courses and score colors
/// too, so it is the one worth keeping if the phone is lost. Only JSON can be
/// imported back.
Future<void> _runExport(
  BuildContext context,
  GolfStore store,
  String format,
) async {
  final isCsv = format == 'csv';
  final messenger = ScaffoldMessenger.of(context);
  final at = DateTime.now();
  final result = await writeBackupFile(
    // The timestamp is the suggested name, so accepting the dialog as-is
    // still gives a name worth keeping, and a second export an hour later
    // does not overwrite the first.
    backupFilename(isCsv ? 'csv' : 'json', at: at),
    isCsv ? store.exportRoundsCsv() : store.exportRoundsJson(),
    mimeType: isCsv ? 'text/csv' : 'application/json',
  );
  final message = switch (result) {
    // Backing out of the save dialog is not an error, so say nothing.
    BackupCancelled() => null,
    BackupFailed(:final reason) => 'Export failed: $reason',
    // Only the file name: a full path does not fit in a snackbar, and the
    // user just chose the location anyway.
    BackupWritten(:final where) => 'Saved $where',
  };
  if (message == null) return;
  messenger.showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 6)),
  );
}

/// Restores a JSON backup.
///
/// Nothing is written to the store until the whole file has parsed, so a
/// truncated or unrelated file leaves the history exactly as it was. What
/// would be added is confirmed first, because an import is the one action
/// here that can add a lot of rounds at once and it should never be the
/// thing the user does by reflex.
Future<void> _runImport(BuildContext context, GolfStore store) async {
  final messenger = ScaffoldMessenger.of(context);
  final String text;
  try {
    final picked = await pickBackupFile();
    if (picked == null) return; // cancelled
    text = picked;
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('That file could not be opened.')),
    );
    return;
  }

  Backup backup;
  try {
    backup = parseBackup(text);
  } on BackupFormatException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return;
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('That file is not a ghin-golf backup.')),
    );
    return;
  }

  if (!context.mounted) return;
  // Ask whether there is anything here of the *whole* backup. Checking rounds
  // alone used to report "nothing new" and stop, throwing away courses,
  // colors and photos that the app was actually missing.
  final p = store.previewBackup(backup);
  final nothingNew =
      p.roundsAdded == 0 &&
      p.coursesAdded == 0 &&
      p.colorsChanged == 0 &&
      p.photosRestored == 0 &&
      !p.themeChanged;
  if (nothingNew) {
    messenger.showSnackBar(
      SnackBar(content: Text(_nothingNewMessage(backup, p))),
    );
    return;
  }

  if (!context.mounted) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Restore backup?'),
      content: Text(_restoreSummary(p)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Restore'),
        ),
      ],
    ),
  );
  if (ok != true) return;

  final r = await store.importBackup(backup);
  final done = <String>[
    if (r.added > 0) _plural(r.added, 'round'),
    if (r.coursesAdded > 0) _plural(r.coursesAdded, 'course'),
    if (r.photosRestored > 0) _plural(r.photosRestored, 'photo'),
  ];
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        done.isEmpty
            ? 'Nothing in that backup was missing.'
            : 'Restored ${done.join(', ')}'
                  '${r.skipped > 0 ? ', ${r.skipped} already present' : ''}.',
      ),
    ),
  );
}

Future<void> _runImportCsv(BuildContext context, GolfStore store) async {
  final messenger = ScaffoldMessenger.of(context);
  final String text;
  try {
    final picked = await pickBackupFile(kind: BackupKind.csv);
    if (picked == null) return; // cancelled
    text = picked;
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('That file could not be opened.')),
    );
    return;
  }

  List<CsvRound> rows;
  try {
    rows = parseCsv(text);
  } on CsvFormatException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return;
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('That file is not a ghin-golf CSV.')),
    );
    return;
  }

  if (!context.mounted) return;
  final p = store.previewCsv(rows);
  if (p.roundsAdded == 0) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Nothing new in that file — ${_plural(rows.length, 'round')} '
          'read, all of them already posted.',
        ),
      ),
    );
    return;
  }

  if (!context.mounted) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Import CSV?'),
      content: Text(_csvSummary(p)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Import'),
        ),
      ],
    ),
  );
  if (ok != true) return;

  final r = store.importCsv(rows);
  final done = <String>[
    if (r.added > 0) _plural(r.added, 'round'),
    if (r.coursesAdded > 0) _plural(r.coursesAdded, 'new course'),
  ];
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        done.isEmpty
            ? 'Nothing in that file was missing.'
            : 'Imported ${done.join(', ')}'
                  '${r.skipped > 0 ? ', ${r.skipped} already posted' : ''}.',
      ),
      // A reconstructed course is a stand-in built from a row's par total, not
      // the real layout, and the user needs to know which courses those are
      // before they start trusting their differentials.
      duration: r.coursesAdded > 0
          ? const Duration(seconds: 8)
          : const Duration(seconds: 4),
      action: r.coursesAdded > 0
          ? SnackBarAction(
              label: 'Undo',
              onPressed: () => _undoCsvImport(context, store, r.roundIds),
            )
          : null,
    ),
  );
}

/// Undoes a CSV import.
///
/// Deletes by the ids the import captured rather than by count, so a round the
/// user posted in the meantime is never the one that disappears.
void _undoCsvImport(BuildContext context, GolfStore store, List<String> ids) {
  final messenger = ScaffoldMessenger.of(context);
  final removed = store.removeRounds(ids);
  if (removed == 0) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Those rounds are already gone.')),
    );
    return;
  }
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        'Removed $removed imported ${removed == 1 ? 'round' : 'rounds'}.',
      ),
    ),
  );
}

String _csvSummary(CsvPreview p) {
  final b = StringBuffer('Adds ${_plural(p.roundsAdded, 'round')}');
  if (p.coursesAdded > 0) {
    b.write(
      ' and creates ${_plural(p.coursesAdded, 'course')} the app does not '
      'have. A created course keeps the par total from the file spread evenly '
      'across its holes, so edit the pars before trusting its differentials.',
    );
  } else {
    b.write(', matched to courses you already have.');
  }
  if (p.roundsSkipped > 0) {
    b.write(
      ' ${_plural(p.roundsSkipped, 'round')} already posted will be skipped.',
    );
  }
  return b.toString();
}

/// One line per kind of thing the restore will bring in, so the confirmation
/// says the same thing the backup actually carries.
String _restoreSummary(BackupPreview p) {
  final parts = <String>[
    if (p.roundsAdded > 0) _plural(p.roundsAdded, 'round'),
    if (p.coursesAdded > 0) _plural(p.coursesAdded, 'course'),
    if (p.colorsChanged > 0)
      '${p.colorsChanged} score ${p.colorsChanged == 1 ? 'color' : 'colors'}',
    if (p.photosRestored > 0) _plural(p.photosRestored, 'photo'),
    if (p.themeChanged) 'appearance',
  ];
  if (p.themeChanged && parts.length == 1) {
    return 'Restores the appearance setting from the backup.';
  }
  return 'Adds ${parts.join(', ')}. '
      'Rounds and courses you already have are left alone, '
      'and nothing is deleted.';
}

/// Shown when the backup holds nothing this app is missing. Worth naming what
/// the file *did* contain, because the usual cause is importing a backup you
/// already restored rather than a wrong file.
String _nothingNewMessage(Backup b, BackupPreview p) {
  final held = <String>[
    if (b.rounds.isNotEmpty) _plural(b.rounds.length, 'round'),
    if (b.courses.isNotEmpty) _plural(b.courses.length, 'course'),
    if (b.scoreColors != null && b.scoreColors!.isNotEmpty) 'settings',
    if (b.photos.isNotEmpty) _plural(b.photos.length, 'photo'),
    if (b.themeMode != null) 'appearance',
  ];
  if (held.isEmpty) return 'That backup is empty.';
  return 'Nothing new: this backup has ${held.join(', ')}, '
      'all of which are already here.';
}

String _plural(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';

/// Score color picker: one row per bucket (eagle … triple), tap a row
/// to choose from preset swatches. Saved to the store, so the hole
/// strip and score entry all follow immediately.
Future<void> showScoreColorsDialog(BuildContext context, GolfStore store) {
  return showDialog(
    context: context,
    builder: (_) => ScoreColorsDialog(store: store),
  );
}

class ScoreColorsDialog extends StatefulWidget {
  final GolfStore store;
  const ScoreColorsDialog({super.key, required this.store});
  @override
  State<ScoreColorsDialog> createState() => _ScoreColorsDialogState();
}

class _ScoreColorsDialogState extends State<ScoreColorsDialog> {
  int? openDiff;
  static const _presets = [
    0xFF1B5E20,
    0xFF2E7D32,
    0xFF43A047,
    0xFF00897B,
    0xFF1565C0,
    0xFF607D8B,
    0xFF9E9E9E,
    0xFF212121,
    0xFFF9A825,
    0xFFEF6C00,
    0xFFE65100,
    0xFFD32F2F,
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Score colors'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final (d, label) in scoreColorLabels)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(widget.store.scoreColorValue(d)),
                      ),
                    ),
                    title: Text(label),
                    trailing: Icon(
                      openDiff == d ? Icons.expand_less : Icons.expand_more,
                    ),
                    onTap: () =>
                        setState(() => openDiff = openDiff == d ? null : d),
                  ),
                  if (openDiff == d)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final p in _presets)
                            InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () => widget.store.setScoreColor(d, p),
                              child: Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Color(p),
                                  border: Border.all(
                                    color: widget.store.scoreColorValue(d) == p
                                        ? Colors.white
                                        : Colors.transparent,
                                    width: 3,
                                  ),
                                ),
                                child: widget.store.scoreColorValue(d) == p
                                    ? const Icon(
                                        Icons.check,
                                        size: 18,
                                        color: Colors.white,
                                      )
                                    : null,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => widget.store.resetScoreColors(),
          child: const Text('Reset defaults'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

String courseName(GolfStore s, Round r) {
  final c = s.courseById(r.courseId);
  final t = s.teeById(r.courseId, r.teeId);
  return '${c?.name ?? '?'} (${t?.name ?? '?'})';
}

/// Everything a round's row shows that comes from the tee it was played from.
///
/// One lookup rather than three: the row is built for ten rounds at a time and
/// each lookup is a scan of the course's tee list.
typedef TeeFacts = ({int par, double? rating, int? slope});

/// Par for the holes actually played, plus that tee's rating and slope.
///
/// Par is deliberately not `tee.par`: a nine played off the 5th is scored
/// against that nine's par, and the difference is several strokes, not
/// rounding. When the tee is gone the rating and slope are null rather than
/// zero, because a slope of 0 would be a lie and a row that still renders is
/// worth more than one that throws.
/// The rows for the recent list, newest first as given.
///
/// A loop rather than a collection-for so the tee is looked up once per round
/// and the three facts come out of the same lookup.
List<RecentRound> recentRows(GolfStore s, List<Round> rounds) {
  final out = <RecentRound>[];
  for (final r in rounds) {
    final f = teeFactsFor(s, r);
    out.add(
      RecentRound(
        round: r,
        courseName: courseName(s, r),
        par: f.par,
        rating: f.rating,
        slope: f.slope,
      ),
    );
  }
  return out;
}

TeeFacts teeFactsFor(GolfStore s, Round r) {
  final tee = s.teeById(r.courseId, r.teeId);
  if (tee == null) return (par: 72, rating: null, slope: null);
  return (
    par: tee.parTotalFrom(r.startHole, r.holes.length),
    rating: tee.rating,
    slope: tee.slope,
  );
}

/// Small stepper button: themed outline circle, shared by score entry.
/// Pass [color] to tint the ring + icon (defaults to theme primary).
Widget outlineStep(
  BuildContext context,
  IconData icon,
  VoidCallback onTap, {
  Color? color,
}) {
  final scheme = Theme.of(context).colorScheme;
  final c = color ?? scheme.primary;
  return InkWell(
    borderRadius: BorderRadius.circular(22),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: c, width: 1.5),
      ),
      child: Icon(icon, size: 16, color: c),
    ),
  );
}

class TrendSpark extends StatelessWidget {
  final List<Round> rounds;
  final GolfStore store;
  final bool light;
  const TrendSpark({
    super.key,
    required this.rounds,
    required this.store,
    this.light = false,
  });
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SparkPainter(
        values: _diffs(),
        color: light ? Colors.white : Colors.green,
      ),
      size: const Size(double.infinity, 48),
    );
  }

  List<double> _diffs() {
    final asc = List<Round>.from(rounds)
      ..sort((a, b) => a.playedAt.compareTo(b.playedAt));
    // The trailing 20, the same window the handicap index averages. Taking
    // the *first* 20 instead would redraw the sparkline from rounds the
    // handicap has already forgotten every time a new one is posted.
    final recent = asc.length > 20 ? asc.sublist(asc.length - 20) : asc;
    final out = <double>[];
    for (final r in recent) {
      final t = store.teeById(r.courseId, r.teeId);
      final d = t == null ? null : r.differential(t);
      if (d != null) out.add(d);
    }
    return out;
  }
}

class _SparkPainter extends CustomPainter {
  final List<double> values;
  final Color color;
  _SparkPainter({required this.values, this.color = Colors.green});
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    if (values.length < 2) {
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        p,
      );
      return;
    }
    final lo = values.reduce((a, b) => a < b ? a : b);
    final hi = values.reduce((a, b) => a > b ? a : b);
    final span = (hi - lo) == 0 ? 1.0 : (hi - lo);
    final pts = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      pts.add(
        Offset(
          size.width * i / (values.length - 1),
          size.height - 4 - (values[i] - lo) / span * (size.height - 8),
        ),
      );
    }
    // PointMode.lines, not polygon: polygon also joins the last point back to
    // the first, which draws a diagonal straight across the trend.
    canvas.drawPoints(PointMode.lines, pts, p);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) =>
      old.values != values || old.color != color;
}

// ---------------- POST ----------------
class PostPage extends StatefulWidget {
  final GolfStore store;

  /// When set, the page corrects this round instead of posting a new one:
  /// the scores start where they were and saving overwrites the original.
  final Round? existing;
  const PostPage({super.key, required this.store, this.existing});
  @override
  State<PostPage> createState() => _PostPageState();
}

class _PostPageState extends State<PostPage> {
  String? courseId;
  String? teeId;
  int holesCount = 18;
  int startHole = 0; // 0 = front nine, 9 = back nine
  bool incompleteRoundReasonValid = false;
  late DateTime playedAt;
  late List<HoleScore> holes;
  int sel = 0; // hole being edited (quick entry)
  final _stripCtrl = ScrollController();
  double _stripW = 0;

  @override
  void dispose() {
    _stripCtrl.dispose();
    super.dispose();
  }

  /// Keeps the selected hole chip centered in the strip after it moves.
  void _centerSelSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_stripCtrl.hasClients || holes.isEmpty || _stripW <= 0) return;
      const itemW = 52.0; // 46 chip + 6 separator
      final x = sel * itemW + itemW / 2 - _stripW / 2;
      _stripCtrl.animateTo(
        x.clamp(0.0, _stripCtrl.position.maxScrollExtent),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _selectHole(int i) {
    setState(() => sel = i.clamp(0, holes.length - 1));
    _centerSelSoon();
  }

  Future<void> _pickRoundDate() async {
    final initialDate = DateUtils.dateOnly(playedAt.toLocal());
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: initialDate.isBefore(DateTime(1900))
          ? initialDate
          : DateTime(1900),
      lastDate: initialDate.isAfter(today) ? initialDate : today,
    );
    if (picked == null || !mounted) return;

    final previousLocal = playedAt.toLocal();
    setState(() {
      playedAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        previousLocal.hour,
        previousLocal.minute,
        previousLocal.second,
        previousLocal.millisecond,
        previousLocal.microsecond,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    playedAt = existing?.playedAt ?? DateTime.now();
    if (existing != null) {
      courseId = existing.courseId;
      teeId = existing.teeId;
      startHole = existing.startHole;
      incompleteRoundReasonValid = existing.incompleteRoundReasonValid;
      // Copied, so abandoning the edit leaves the stored round alone.
      holes = existing.holes.map((h) => h.copy()).toList();
      holesCount = holes.length;
      sel = 0;
      return;
    }
    if (widget.store.courses.isNotEmpty) {
      courseId = widget.store.courses.first.id;
      teeId = widget.store.courses.first.defaultTee.id;
      holes = List.generate(18, (i) => HoleScore(score: _parFor(i)));
    } else {
      holes = [];
    }
  }

  int _parFor(int i) {
    final t = _tee();
    if (t == null) return 4;
    final idx = startHole + i;
    if (idx < 0 || idx >= t.holes.length) return 4;
    return t.holes[idx].par;
  }

  Tee? _tee() => (courseId == null || teeId == null)
      ? null
      : widget.store.teeById(courseId!, teeId!);

  void _resetScores() {
    setState(() {
      incompleteRoundReasonValid = false;
      holes = List.generate(holesCount, (i) => HoleScore(score: _parFor(i)));
      sel = 0;
    });
  }

  int _parAt(int i, Tee? tee) {
    if (tee == null) return 4;
    final idx = startHole + i;
    if (idx < 0 || idx >= tee.holes.length) return 4;
    return tee.holes[idx].par;
  }

  /// Score-vs-par color scale, shared by the hole strip and score entry.
  /// User-editable on Post Score (palette icon), persisted in store.
  Color _diffColor(int d) => Color(widget.store.scoreColorValue(d));

  Color _scoreColor(BuildContext context, int score, int par) =>
      _diffColor(score - par);

  TextStyle _choiceLabelStyle(BuildContext context, bool selected) {
    final scheme = Theme.of(context).colorScheme;
    return TextStyle(
      color: selected ? scheme.onSecondaryContainer : scheme.onSurface,
    );
  }

  Color _readableForeground(Color background) =>
      background.computeLuminance() > 0.179 ? Colors.black : Colors.white;

  void _setScore(int i, int score, {bool advance = false}) {
    setState(() {
      holes[i].score = score.clamp(1, 12);
      holes[i].sanitize();
      if (advance && i + 1 < holes.length) sel = i + 1;
    });
    _centerSelSoon();
  }

  @override
  Widget build(BuildContext context) {
    final courses = widget.store.courses;
    if (courses.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Post Score')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'No courses yet. Go to Courses tab and add your local course first.',
            ),
          ),
        ),
      );
    }
    // The course/tee fallbacks below rebuild `holes` from par, which would wipe
    // the very scores an edit was opened to correct. So a round being edited
    // keeps its scores, and is only repointed if its course is really gone.
    final editing = widget.existing != null;
    if (courseId == null || !courses.any((c) => c.id == courseId)) {
      courseId = courses.first.id;
      teeId = courses.first.defaultTee.id;
      if (!editing) {
        holes = List.generate(holesCount, (i) => HoleScore(score: _parFor(i)));
      }
    }
    final course = courses.firstWhere(
      (c) => c.id == courseId,
      orElse: () => courses.first,
    );
    if (teeId == null || !course.tees.any((t) => t.id == teeId)) {
      teeId = course.defaultTee.id;
      if (!editing) {
        holes = List.generate(holesCount, (i) => HoleScore(score: _parFor(i)));
      }
    }
    final tee = _tee();
    final holeCountTee =
        tee ??
        course.tees.firstWhere(
          (t) => t.id == teeId,
          orElse: () => course.defaultTee,
        );
    if (sel >= holes.length) sel = holes.isEmpty ? 0 : holes.length - 1;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Edit Round' : 'Post Score'),
        actions: [
          IconButton(
            tooltip: 'Score colors',
            icon: const Icon(Icons.palette_outlined),
            onPressed: () => showScoreColorsDialog(context, widget.store),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(Insets.gutter),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: courseId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Course'),
                    items: [
                      for (final c in courses)
                        DropdownMenuItem(value: c.id, child: Text(c.name)),
                    ],
                    onChanged: (v) => setState(() {
                      courseId = v!;
                      final nc = courses.firstWhere((c) => c.id == v);
                      teeId = nc.defaultTee.id;
                      holesCount = nc.defaultTee.holes.length == 18 ? 18 : 9;
                      startHole = 0;
                      _resetScores();
                    }),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: teeId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Tee'),
                    items: [
                      for (final t in course.tees)
                        DropdownMenuItem(
                          value: t.id,
                          child: Text('${t.name} • ${t.rating}/${t.slope}'),
                        ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      final selectedTee = course.tees.firstWhere(
                        (t) => t.id == v,
                      );
                      setState(() {
                        teeId = v;
                        if (!holeCountOptionsForTee(
                          selectedTee.holes.length,
                        ).contains(holesCount)) {
                          holesCount = selectedTee.holes.length == 18 ? 18 : 9;
                        }
                        startHole = 0;
                        _resetScores();
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    key: const ValueKey('play-hole-count-selector'),
                    initialValue: holesCount,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Holes'),
                    items: [
                      for (final n in holeCountOptionsForTee(
                        holeCountTee.holes.length,
                      ))
                        DropdownMenuItem(value: n, child: Text('$n Holes')),
                    ],
                    onChanged: (n) {
                      if (n == null) return;
                      setState(() {
                        holesCount = n;
                        startHole = 0;
                        _resetScores();
                      });
                    },
                  ),
                  if (editing) ...[
                    const SizedBox(height: 8),
                    ListTile(
                      key: const ValueKey('edit-round-date'),
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.calendar_month_outlined),
                      title: const Text('Round date'),
                      subtitle: Text(
                        MaterialLocalizations.of(
                          context,
                        ).formatMediumDate(playedAt.toLocal()),
                      ),
                      trailing: TextButton.icon(
                        onPressed: _pickRoundDate,
                        icon: const Icon(Icons.edit_calendar_outlined),
                        label: const Text('Change'),
                      ),
                    ),
                  ],
                  if (holesCount >= 10 && holesCount < 18)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: incompleteRoundReasonValid,
                      title: const Text(
                        'I had a valid reason for not completing the round',
                      ),
                      onChanged: (value) => setState(
                        () => incompleteRoundReasonValid = value ?? false,
                      ),
                    ),
                  if (holesCount == 9) ...[
                    const SizedBox(height: 8),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 0, label: Text('Front 9')),
                        ButtonSegment(value: 9, label: Text('Back 9')),
                      ],
                      selected: {startHole},
                      onSelectionChanged: (s) => setState(() {
                        startHole = s.first;
                        _resetScores();
                      }),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          LayoutBuilder(
            builder: (ctx, cons) {
              _stripW = cons.maxWidth;
              return SizedBox(
                height: 60,
                child: ListView.separated(
                  controller: _stripCtrl,
                  scrollDirection: Axis.horizontal,
                  itemCount: holes.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (ctx, i) {
                    final par = _parAt(i, tee);
                    final active = i == sel;
                    final col = _scoreColor(context, holes[i].score, par);
                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _selectHole(i),
                      child: Container(
                        width: 46,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: col,
                          border: active
                              ? Border.all(
                                  color: _readableForeground(col),
                                  width: 2,
                                )
                              : null,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '${i + 1}',
                              style: TextStyle(
                                fontSize: 11,
                                color: _readableForeground(col),
                              ),
                            ),
                            Text(
                              '${holes[i].score}',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: _readableForeground(col),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
          if (holes.isNotEmpty) const SizedBox(height: Insets.md),
          if (holes.isNotEmpty) _quickEditor(sel, tee),
          FilledButton.icon(
            icon: const Icon(Icons.check),
            label: Text(
              editing
                  ? 'Update ${holes.fold(0, (s, h) => s + h.score)} total'
                  : 'Save ${holes.fold(0, (s, h) => s + h.score)} total',
            ),
            onPressed: _save,
          ),
        ],
      ),
    );
  }

  Widget _statRow(String label, Widget controls) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      SizedBox(
        width: 84,
        child: Text(
          label,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
      ),
      Expanded(
        child: Padding(
          key: ValueKey('play-controls-${label.toLowerCase()}'),
          padding: const EdgeInsets.only(right: Insets.lg),
          child: Align(alignment: Alignment.centerLeft, child: controls),
        ),
      ),
    ],
  );

  /// Compact stepper controls, kept together in the right-hand column.
  Widget _statStepper({
    required String value,
    required VoidCallback onMinus,
    required VoidCallback onPlus,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        outlineStep(context, Icons.remove, onMinus),
        SizedBox(
          width: 36,
          child: Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
        ),
        outlineStep(context, Icons.add, onPlus),
      ],
    );
  }

  /// One hole on screen: one-tap score vs par (auto-advances), then
  /// putts/fairway/penalties/drive only if you want them.
  Widget _quickEditor(int i, Tee? tee) {
    final h = holes[i];
    final par = _parAt(i, tee);
    const quick = [
      (-2, 'Eagle'),
      (-1, 'Birdie'),
      (0, 'Par'),
      (1, 'Bogey'),
      (2, 'Double'),
      (3, 'Triple'),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TextButton(
                  key: const ValueKey('play-prev-hole'),
                  onPressed: i > 0 ? () => _selectHole(i - 1) : null,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                  child: const Text('< Prev'),
                ),
                Expanded(
                  child: Text(
                    'Hole ${i + 1} • Par $par',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                TextButton(
                  key: const ValueKey('play-next-hole'),
                  onPressed: i + 1 < holes.length
                      ? () => _selectHole(i + 1)
                      : null,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                  child: const Text('Next >'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (d, label) in quick)
                  Builder(
                    builder: (ctx) {
                      final c = _diffColor(d);
                      final isSel = h.score == (par + d).clamp(1, 12);
                      final scheme = Theme.of(ctx).colorScheme;
                      return ChoiceChip(
                        label: Text(
                          label,
                          style: TextStyle(
                            color: isSel
                                ? _readableForeground(c)
                                : scheme.onSurface,
                          ),
                        ),
                        selected: isSel,
                        selectedColor: c,
                        backgroundColor: c.withValues(alpha: 0.18),
                        side: BorderSide(color: c.withValues(alpha: 0.9)),
                        onSelected: (_) => _setScore(i, par + d, advance: true),
                      );
                    },
                  ),
              ],
            ),
            const Divider(),
            _statRow(
              'GIR',
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ChoiceChip(
                    label: Text(
                      'Yes',
                      style: _choiceLabelStyle(context, h.gir),
                    ),
                    selected: h.gir,
                    selectedColor: Theme.of(
                      context,
                    ).colorScheme.secondaryContainer,
                    onSelected: (_) => setState(() => h.gir = true),
                  ),
                  ChoiceChip(
                    label: Text(
                      'No',
                      style: _choiceLabelStyle(context, !h.gir),
                    ),
                    selected: !h.gir,
                    selectedColor: Theme.of(
                      context,
                    ).colorScheme.secondaryContainer,
                    onSelected: (_) => setState(() => h.gir = false),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _statRow(
              'Putts',
              _statStepper(
                value: '${h.putts}',
                onMinus: () => setState(() {
                  h.putts = (h.putts - 1).clamp(0, 5);
                  h.sanitize();
                }),
                onPlus: () => setState(() {
                  // Putts never reach the total: one stroke got here.
                  h.putts = (h.putts + 1).clamp(0, (h.score - 1).clamp(0, 5));
                  h.sanitize();
                }),
              ),
            ),
            const SizedBox(height: 8),
            _statRow(
              'Penalty',
              _statStepper(
                value: '${h.penalties}',
                onMinus: () => setState(() {
                  h.penalties = (h.penalties - 1).clamp(0, 4);
                  h.sanitize();
                }),
                onPlus: () => setState(() {
                  h.penalties = (h.penalties + 1).clamp(0, 4);
                  h.sanitize();
                  if (h.score < h.penalties + 1) h.score = h.penalties + 1;
                }),
              ),
            ),
            const SizedBox(height: 8),
            _statRow(
              'Fairway',
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final f in ['L', 'H', 'R'])
                    ChoiceChip(
                      label: Text(
                        f,
                        style: _choiceLabelStyle(context, h.fairway == f),
                      ),
                      selected: h.fairway == f,
                      selectedColor: Theme.of(
                        context,
                      ).colorScheme.secondaryContainer,
                      onSelected: (_) =>
                          setState(() => h.fairway = h.fairway == f ? 'NA' : f),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    final tee = _tee();
    if (tee == null || courseId == null || teeId == null) return;
    if (startHole + holes.length > tee.holes.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'This tee only has ${tee.holes.length} holes, so it cannot hold ${holes.length}.',
          ),
        ),
      );
      return;
    }
    for (final h in holes) {
      h.sanitize();
    }
    // A round being edited keeps its historical handicap snapshot. New rounds
    // use the index in effect before this calendar day, since revisions happen
    // after play for the day is complete.
    final existing = widget.existing;
    final hi = existing != null
        ? existing.handicapIndexAtPlay
        : widget.store.handicapIndexBefore(playedAt);
    final has18HoleRatings =
        tee.holes.length == 18 && startHole == 0 && holes.length >= 10;
    final ch = !has18HoleRatings
        ? null
        : hi == null
        ? existing?.courseHandicap
        : whs_engine.courseHandicap(
            handicapIndex: hi,
            slopeRating: tee.slope.toDouble(),
            courseRating: tee.rating,
            par: tee.par,
          );
    final r = Round(
      // An edit keeps the round identity and playing-handicap snapshot, while
      // allowing the recorded play date to be corrected.
      id: existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      courseId: courseId!,
      teeId: teeId!,
      playedAt: playedAt,
      format: existing?.format ?? 'stroke',
      isTournament: existing?.isTournament ?? false,
      holes: holes,
      pcc: existing?.pcc ?? 0.0,
      incompleteRoundReasonValid: incompleteRoundReasonValid,
      courseHandicap: ch,
      handicapIndexAtPlay: hi,
      startHole: startHole,
    );
    if (existing != null) {
      widget.store.updateRound(r);
    } else {
      widget.store.addRound(r);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          existing != null
              ? 'Updated ${r.totalGross} (CH ${ch ?? '—'}) — '
                    '${selectionLabel(holes.length, startHole)}.'
              : 'Saved ${r.totalGross} (CH ${ch ?? '—'}) — '
                    '${selectionLabel(holes.length, startHole)}.',
        ),
      ),
    );
    if (existing != null) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }
}

/// Full-screen viewer for a saved scorecard photo.
void showCoursePhoto(BuildContext context, String courseName, String path) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => _CoursePhotoViewer(courseName: courseName, path: path),
    ),
  );
}

class _CoursePhotoViewer extends StatefulWidget {
  final String courseName;
  final String path;

  const _CoursePhotoViewer({required this.courseName, required this.path});

  @override
  State<_CoursePhotoViewer> createState() => _CoursePhotoViewerState();
}

class _CoursePhotoViewerState extends State<_CoursePhotoViewer> {
  final _zoom = _ScorecardZoom();

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.courseName} — scorecard')),
      body: Column(
        children: [
          Expanded(
            child: _scorecardImageView(
              widget.path,
              _zoom,
              key: const ValueKey('scorecard-interactive-viewer'),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ScorecardZoomControls(zoom: _zoom),
                  Text(
                    'Pinch to zoom · drag to pan',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScorecardZoom {
  static const minScale = 1.0;
  static const maxScale = 6.0;
  static const zoomFactor = 1.5;

  final transformationController = TransformationController();
  Size viewportSize = Size.zero;

  double get scale => transformationController.value
      .getMaxScaleOnAxis()
      .clamp(minScale, maxScale)
      .toDouble();

  void zoomBy(double factor) {
    final targetScale = (scale * factor).clamp(minScale, maxScale).toDouble();
    if (targetScale == scale || viewportSize.isEmpty) return;

    final focalPoint = viewportSize.center(Offset.zero);
    final scenePoint = transformationController.toScene(focalPoint);
    transformationController.value = Matrix4.identity()
      ..translateByDouble(focalPoint.dx, focalPoint.dy, 0, 1)
      ..scaleByDouble(targetScale, targetScale, targetScale, 1)
      ..translateByDouble(-scenePoint.dx, -scenePoint.dy, 0, 1);
  }

  void reset() {
    transformationController.value = Matrix4.identity();
  }

  void dispose() => transformationController.dispose();
}

Widget _scorecardImageView(String path, _ScorecardZoom zoom, {Key? key}) =>
    LayoutBuilder(
      builder: (context, constraints) {
        zoom.viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
        return InteractiveViewer(
          key: key,
          transformationController: zoom.transformationController,
          minScale: _ScorecardZoom.minScale,
          maxScale: _ScorecardZoom.maxScale,
          boundaryMargin: const EdgeInsets.all(80),
          child: SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: kIsWeb
                ? Image.network(
                    path,
                    fit: BoxFit.contain,
                    alignment: Alignment.center,
                  )
                : Image.file(
                    File(path),
                    fit: BoxFit.contain,
                    alignment: Alignment.center,
                  ),
          ),
        );
      },
    );

class _ScorecardZoomControls extends StatelessWidget {
  final _ScorecardZoom zoom;
  final bool compact;

  const _ScorecardZoomControls({required this.zoom, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final compactStyle = compact
        ? IconButton.styleFrom(
            minimumSize: const Size(44, 44),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          )
        : null;

    return AnimatedBuilder(
      animation: zoom.transformationController,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton.filledTonal(
            tooltip: 'Zoom out',
            onPressed: zoom.scale > _ScorecardZoom.minScale
                ? () => zoom.zoomBy(1 / _ScorecardZoom.zoomFactor)
                : null,
            style: compactStyle,
            icon: const Icon(Icons.zoom_out),
          ),
          SizedBox(width: compact ? 2 : 8),
          SizedBox(
            width: compact ? 40 : 48,
            child: Text(
              '${(zoom.scale * 100).round()}%',
              textAlign: TextAlign.center,
              key: ValueKey(
                compact
                    ? 'course-scorecard-zoom-level'
                    : 'scorecard-zoom-level',
              ),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(width: compact ? 2 : 8),
          IconButton.filledTonal(
            tooltip: 'Zoom in',
            onPressed: zoom.scale < _ScorecardZoom.maxScale
                ? () => zoom.zoomBy(_ScorecardZoom.zoomFactor)
                : null,
            style: compactStyle,
            icon: const Icon(Icons.zoom_in),
          ),
          SizedBox(width: compact ? 2 : 8),
          IconButton.filledTonal(
            tooltip: 'Reset zoom and pan',
            onPressed: zoom.reset,
            style: compactStyle,
            icon: const Icon(Icons.center_focus_strong),
          ),
        ],
      ),
    );
  }
}

/// Phase 0 OCR inspector: shows the raw text Tesseract returned for the
/// last scan (copyable), so a miss can be diagnosed instead of guessed at.
void showOcrTextDialog(BuildContext context, String text) {
  showDialog(
    context: context,
    builder: (_) => OcrTextDialog(text: text),
  );
}

class OcrTextDialog extends StatelessWidget {
  final String text;
  const OcrTextDialog({super.key, required this.text});
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('What the scan read'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: SelectableText(
            text,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: text));
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('OCR text copied.')));
          },
          child: const Text('Copy'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// Header colors sampled from the selected tee box, like a printed card.
///
/// The names come off the scorecard, so a course can have any of them —
/// Purple, Orange and Combo are all real. Every color a tee box can be
/// printed as is mapped here, because an unlisted name used to fall through
/// to teal and render a Purple box green.
///
/// The fallback is a neutral slate rather than a color, so a name this
/// function does not know reads as "no color known" instead of quietly
/// looking like a real tee box. Contrast on the label is picked per color:
/// dark text on the light ones, white on the dark ones.
({Color bg, Color fg}) _teeTheme(String name) {
  switch (name.trim().toLowerCase()) {
    case 'black':
      return (bg: const Color(0xFF212121), fg: Colors.white);
    case 'blue':
      return (bg: const Color(0xFF1565C0), fg: Colors.white);
    case 'white':
      return (bg: const Color(0xFFEEEEEE), fg: const Color(0xFF212121));
    case 'gold':
    case 'yellow':
      return (bg: const Color(0xFFF9A825), fg: const Color(0xFF212121));
    case 'red':
      return (bg: const Color(0xFFC62828), fg: Colors.white);
    case 'green':
      return (bg: const Color(0xFF2E7D32), fg: Colors.white);
    case 'purple':
      return (bg: const Color(0xFF6A1B9A), fg: Colors.white);
    case 'orange':
      return (bg: const Color(0xFFEF6C00), fg: const Color(0xFF212121));
    case 'bronze':
      return (bg: const Color(0xFF8D6E63), fg: Colors.white);
    case 'silver':
    case 'gray':
    case 'grey':
      return (bg: const Color(0xFF78909C), fg: Colors.white);
    default:
      return (bg: const Color(0xFF455A64), fg: Colors.white);
  }
}

/// Scorecard styled like the printed card: tee-colored header, hole
/// numbers, Par and Yds rows, OUT/IN/TOT totals. Front and back nines
/// stack vertically so every hole is reachable by scrolling.
Widget scorecardTable(Course course, Tee tee) {
  final theme = _teeTheme(tee.name);
  final front = tee.holes.take(9).toList();
  final back = tee.holes.skip(9).toList();
  int parSum(List<HoleInfo> hs) => hs.fold(0, (s, h) => s + h.par);
  int ydsSum(List<HoleInfo> hs) => hs.fold(0, (s, h) => s + h.yardage);
  String yds(int y) => y == 0 ? '—' : '$y';

  Widget nine(
    String label,
    List<HoleInfo> hs,
    String outHead, {
    String? inHead,
    int? totPar,
    int? totYds,
  }) {
    final heads = <String>[outHead];
    if (inHead != null) heads.add(inHead);
    // Fixed-width centered cell with a vertical separator on its right
    // (none after the last column), so every hole column lines up.
    Widget cell(
      String s,
      Color border, {
      double width = 36,
      TextStyle? style,
      bool last = false,
    }) {
      return Container(
        width: width,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            right: last ? BorderSide.none : BorderSide(color: border),
          ),
        ),
        child: Text(s, textAlign: TextAlign.center, style: style),
      );
    }

    const headStyle = TextStyle(fontWeight: FontWeight.bold);
    const dataStyle = TextStyle(fontSize: 13);
    const boldData = TextStyle(fontSize: 13, fontWeight: FontWeight.bold);
    final headBorder = theme.fg.withValues(alpha: 0.4);
    final dataBorder = Colors.grey.withValues(alpha: 0.5);
    final lastHead = heads.length - 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 2),
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 4,
            headingRowColor: WidgetStateProperty.all(theme.bg),
            headingTextStyle: TextStyle(
              color: theme.fg,
              fontWeight: FontWeight.bold,
            ),
            dataTextStyle: const TextStyle(fontSize: 13),
            columns: [
              DataColumn(
                label: cell(
                  'Hole',
                  headBorder,
                  width: 52,
                  style: headStyle.copyWith(color: theme.fg),
                ),
              ),
              for (var k = 0; k < hs.length; k++)
                DataColumn(
                  label: cell(
                    '${hs[k].number}',
                    headBorder,
                    style: headStyle.copyWith(color: theme.fg),
                  ),
                ),
              for (var k = 0; k < heads.length; k++)
                DataColumn(
                  label: cell(
                    heads[k],
                    headBorder,
                    last: k == lastHead,
                    style: headStyle.copyWith(color: theme.fg),
                  ),
                ),
            ],
            rows: [
              DataRow(
                cells: [
                  DataCell(cell('Par', dataBorder, width: 52, style: boldData)),
                  for (var k = 0; k < hs.length; k++)
                    DataCell(
                      cell('${hs[k].par}', dataBorder, style: dataStyle),
                    ),
                  DataCell(
                    cell(
                      '${parSum(hs)}',
                      dataBorder,
                      last: inHead == null,
                      style: boldData,
                    ),
                  ),
                  if (inHead != null)
                    DataCell(
                      cell('$totPar', dataBorder, last: true, style: boldData),
                    ),
                ],
              ),
              DataRow(
                cells: [
                  DataCell(cell('Yds', dataBorder, width: 52, style: boldData)),
                  for (var k = 0; k < hs.length; k++)
                    DataCell(
                      cell(yds(hs[k].yardage), dataBorder, style: dataStyle),
                    ),
                  DataCell(
                    cell(
                      yds(ydsSum(hs)),
                      dataBorder,
                      last: inHead == null,
                      style: boldData,
                    ),
                  ),
                  if (inHead != null)
                    DataCell(
                      cell(
                        yds(totYds ?? 0),
                        dataBorder,
                        last: true,
                        style: boldData,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          color: theme.bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              course.name,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: theme.fg,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${tee.name} tees • Rating ${tee.rating} • Slope ${tee.slope} • Par ${tee.par} • ${tee.yardage} yd',
              style: TextStyle(
                fontSize: 12,
                color: theme.fg.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
      ),
      nine('FRONT 9', front, 'OUT'),
      if (back.isNotEmpty)
        nine(
          'BACK 9',
          back,
          'IN',
          inHead: 'TOT',
          totPar: parSum(tee.holes),
          totYds: ydsSum(tee.holes),
        ),
    ],
  );
}

// ---------------- COURSES ----------------
class CoursesPage extends StatefulWidget {
  final GolfStore store;
  const CoursesPage({super.key, required this.store});
  @override
  State<CoursesPage> createState() => _CoursesPageState();
}

class _CoursesPageState extends State<CoursesPage> {
  String q = '';
  String? selectedCourseId;
  String? selectedTeeId;
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _api = OpenGolfApi();
  Timer? _debounce;
  List<OpenGolfCourse> onlineResults = [];
  String? onlineError;
  bool onlineBusy = false;
  final Set<String> importingIds = {};

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Single search box: saved courses filter instantly on every keystroke;
  /// the online open database follows after a short pause (3+ chars).
  void _onSearchChanged(String v) {
    setState(() => q = v);
    _debounce?.cancel();
    if (v.trim().length < 3) {
      setState(() {
        onlineResults = [];
        onlineError = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 600), _onlineSearch);
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final local = store.searchCourses(q);
    // Keep the selection stable while typing: only reset when the
    // selected course no longer exists (deleted).
    if (selectedCourseId == null ||
        store.courseById(selectedCourseId!) == null) {
      selectedCourseId = local.isNotEmpty ? local.first.id : null;
      selectedTeeId = null;
    }
    final course = selectedCourseId == null
        ? null
        : store.courseById(selectedCourseId!);
    if (course != null &&
        (selectedTeeId == null ||
            !course.tees.any((t) => t.id == selectedTeeId))) {
      selectedTeeId = course.defaultTee.id;
    }
    final tee = course == null
        ? null
        : (store.teeById(course.id, selectedTeeId ?? '') ?? course.defaultTee);

    return Scaffold(
      appBar: AppBar(title: const Text('Courses')),
      body: ListView(
        padding: const EdgeInsets.all(Insets.gutter),
        children: [
          TextField(
            key: const ValueKey('course-search'),
            controller: _searchController,
            focusNode: _searchFocus,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search courses',
            ),
            onChanged: _onSearchChanged,
          ),
          if (q.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Online matches (US open database)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                if (onlineBusy)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            if (onlineError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  onlineError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            for (final r in onlineResults)
              Card(
                margin: const EdgeInsets.only(top: Insets.sm),
                child: ListTile(
                  leading: const Icon(Icons.public_outlined),
                  title: Text(r.name),
                  subtitle: Text(
                    r.subtitle.isEmpty ? 'Open database match' : r.subtitle,
                  ),
                  trailing: importingIds.contains(r.id)
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : TextButton(
                          onPressed: () => _importOnline(r),
                          child: const Text('Import'),
                        ),
                  onTap: () => _importOnline(r),
                ),
              ),
            if (onlineResults.isNotEmpty || onlineError != null)
              Text(
                openGolfAttribution,
                style: AppType.meta.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
            const Divider(),
          ],
          const SizedBox(height: 4),
          Text(
            'SAVED ON THIS DEVICE',
            style: AppType.meta.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (local.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'No saved courses match.',
                style: AppType.meta.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          for (final c in local)
            Card(
              margin: const EdgeInsets.only(top: Insets.sm),
              color: c.id == selectedCourseId
                  ? Theme.of(context).colorScheme.primaryContainer
                  : null,
              child: ListTile(
                selected: c.id == selectedCourseId,
                selectedColor: Theme.of(context).colorScheme.onPrimaryContainer,
                leading: Icon(
                  c.id == selectedCourseId
                      ? Icons.golf_course
                      : Icons.golf_course_outlined,
                  color: c.id == selectedCourseId
                      ? Theme.of(context).colorScheme.onPrimaryContainer
                      : Theme.of(context).colorScheme.primary,
                ),
                title: InkWell(
                  key: ValueKey('course-name-${c.id}'),
                  onTap: c.custom ? () => _openEditCourse(c) : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(c.name),
                  ),
                ),
                subtitle: Text(
                  [
                    // A scanned card does not always say where the course is, and
                    // a dangling ", " looks like a bug rather than a blank.
                    [c.city, c.state].where((p) => p.isNotEmpty).join(', '),
                    '${c.tees.length} tee${c.tees.length == 1 ? '' : 's'}',
                  ].where((p) => p.isNotEmpty).join(' • '),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Remove course',
                  onPressed: () => _confirmDelete(c),
                ),
                onTap: () => setState(() {
                  selectedCourseId = c.id;
                  selectedTeeId = c.defaultTee.id;
                }),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _openAddCourse(),
              icon: const Icon(Icons.add),
              label: const Text('Add manually'),
            ),
          ),
          const Divider(),
          if (course == null || tee == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No course selected. Search above, import one, or add it manually.',
              ),
            ),
          if (course != null && tee != null) ...[
            SizedBox(
              width: double.infinity,
              child: DropdownButton<String>(
                value: tee.id,
                isExpanded: true,
                items: [
                  for (final t in course.tees)
                    DropdownMenuItem(
                      value: t.id,
                      child: Text(
                        '${t.name} • ${t.rating}/${t.slope} • Par ${t.par}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => selectedTeeId = v),
              ),
            ),
            scorecardTable(course, tee),
            if (photoUsable(course.imagePath))
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () =>
                      showCoursePhoto(context, course.name, course.imagePath),
                  icon: const Icon(Icons.photo_outlined),
                  label: const Text('View scorecard photo'),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _onlineSearch() async {
    final query = q;
    setState(() {
      onlineBusy = true;
      onlineError = null;
    });
    try {
      final results = await _api.search(query);
      // Drop stale responses if the user kept typing.
      if (!mounted || query != q) return;
      setState(() {
        onlineResults = results;
        if (results.isEmpty) {
          onlineError = 'No online matches. Add it manually below.';
        }
      });
    } on OpenGolfException catch (e) {
      if (!mounted || query != q) return;
      setState(() => onlineError = e.message);
    } catch (e) {
      // json.decode can throw a FormatException on a malformed
      // response, which OpenGolfException would not catch.
      if (!mounted || query != q) return;
      setState(() => onlineError = e.toString());
    } finally {
      if (mounted && query == q) setState(() => onlineBusy = false);
    }
  }

  Future<void> _importOnline(OpenGolfCourse r) async {
    setState(() => importingIds.add(r.id));
    try {
      final detail = await _api.fetchCourse(r.id);
      // Tee boxes carry the rating and slope the handicap maths needs, so they
      // are fetched before the form opens. A failure here is not fatal: the
      // form still opens and falls back to one blank tee box to type into.
      var built = <Tee>[];
      try {
        final card = await _api.fetchScorecard(r.id);
        built = teesFromScorecard(r.id, card.tees, card.holes) ?? <Tee>[];
      } catch (_) {
        built = <Tee>[];
      }
      if (!mounted) return;
      setState(() => importingIds.remove(r.id));
      await _openAddCourse(initial: detail, importedTees: built);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        importingIds.remove(r.id);
        onlineError = e.toString();
      });
    }
  }

  Future<void> _openEditCourse(Course c) async {
    final updated = await Navigator.of(context).push<Course>(
      MaterialPageRoute(builder: (_) => AddCourseScreen(existing: c)),
    );
    if (updated != null) {
      widget.store.updateCourse(updated);
      setState(() {
        selectedCourseId = updated.id;
        selectedTeeId = updated.defaultTee.id;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${updated.name} updated.')));
      }
    }
  }

  Future<void> _openAddCourse({
    OpenGolfDetail? initial,
    List<Tee> importedTees = const [],
  }) async {
    final created = await Navigator.of(context).push<Course>(
      MaterialPageRoute(
        builder: (_) =>
            AddCourseScreen(initial: initial, importedTees: importedTees),
      ),
    );
    if (created != null) {
      widget.store.addCourse(created);
      _searchFocus.unfocus();
      _searchController.clear();
      setState(() {
        q = '';
        selectedCourseId = created.id;
        selectedTeeId = created.defaultTee.id;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${created.name} added — it now appears in search and scoring.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _confirmDelete(Course c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${c.name}?'),
        content: const Text(
          'Rounds already posted here are kept, but the course disappears from search and scoring.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      widget.store.deleteCourse(c.id);
      await deleteScanPhoto(c.imagePath);
      setState(() {
        if (selectedCourseId == c.id) selectedCourseId = null;
      });
    }
  }
}

// ---------------- ADD COURSE ----------------
class AddCourseScreen extends StatefulWidget {
  /// When set (online import), name/city/state/pars are prefilled from the
  /// open database's course record.
  final OpenGolfDetail? initial;

  /// Tee boxes read from the database's tee and hole endpoints for [initial].
  ///
  /// The open data does carry rating and slope, so an imported tee arrives
  /// complete and the form only needs checking. Empty when the course was not
  /// imported or the database had no usable tee, in which case the form falls
  /// back to a single blank tee box for the user to type into.
  final List<Tee> importedTees;

  /// When set, the form edits this saved custom course instead of adding.
  final Course? existing;
  const AddCourseScreen({
    super.key,
    this.initial,
    this.existing,
    this.importedTees = const [],
  });
  @override
  State<AddCourseScreen> createState() => _AddCourseScreenState();
}

/// One tee box being drafted in the add-course form. Pars are shared at
/// course level; each tee has its own rating/slope and per-hole yardages.
class _TeeDraft {
  final TextEditingController nameCtrl;
  final TextEditingController ratingCtrl = TextEditingController();
  final TextEditingController slopeCtrl = TextEditingController();
  List<int> yards;
  _TeeDraft(String name, int holes)
    : nameCtrl = TextEditingController(text: name),
      yards = List.filled(holes, 0);

  /// A tee the database already knows: rating, slope and yardage come across
  /// filled in, so nothing has to be retyped and nothing is guessed.
  factory _TeeDraft.fromTee(Tee t) {
    final d = _TeeDraft(t.name, t.holes.length)
      ..ratingCtrl.text = t.rating.toStringAsFixed(1)
      ..slopeCtrl.text = '${t.slope}'
      ..yards = [for (final h in t.holes) h.yardage];
    return d;
  }

  void resize(int holes) {
    if (yards.length == holes) return;
    yards = List.generate(holes, (i) => i < yards.length ? yards[i] : 0);
  }

  void dispose() {
    nameCtrl.dispose();
    ratingCtrl.dispose();
    slopeCtrl.dispose();
  }
}

class _AddCourseScreenState extends State<AddCourseScreen> {
  final nameCtrl = TextEditingController();
  final cityCtrl = TextEditingController();
  final stateCtrl = TextEditingController();
  final _photoZoom = _ScorecardZoom();
  int holesCount = 18;
  late List<int> pars;
  final List<_TeeDraft> tees = [];
  int editYardsTee = 0;
  bool scanning = false;
  String scanStatus = 'Reading scorecard…';
  XFile? scanPhoto;
  String keptPhoto = '';
  // Raw OCR text from the last scan, viewable via the inspector (Phase 0
  // of the OCR plan): shows what Tesseract actually read, so a miss can
  // be blamed on the input/engine instead of the parser.
  String lastOcrText = '';
  // Every attempt's raw text, not just the best one. A card that reads badly
  // is usually readable in one pass and garbled in another, so keeping the
  // failures is what makes a parser fix testable against a real photo later
  // instead of a guess.
  List<String> lastOcrAttempts = const [];
  // Text from the digits-only pass, kept for the raw-text inspector.
  String lastOcrDigitsText = '';
  // The hOCR from the column-geometry pass, same reason.
  String lastOcrHocrText = '';
  // Holes whose par was guessed from yardage lengths rather than read, and
  // whether the guess came from the yardages at all. The user is asked about
  // these instead of being shown a form that silently filled itself in.
  Set<int> parUncertain = const {};
  bool parFromYardages = false;
  // Stroke index read off the card's handicap row by the last scan, used
  // in preference to the odd/even estimate when it covers every hole.
  List<int> scanHcp = const [];
  static const _suggestNames = [
    'White',
    'Blue',
    'Red',
    'Black',
    'Gold',
    'Green',
  ];

  @override
  void initState() {
    super.initState();
    final edit = widget.existing;
    if (edit != null) {
      nameCtrl.text = edit.name;
      cityCtrl.text = edit.city;
      stateCtrl.text = edit.state;
      holesCount = edit.tees.first.holes.length;
      pars = [for (final h in edit.tees.first.holes) h.par];
      while (pars.length < holesCount) {
        pars.add(4);
      }
      for (final t in edit.tees) {
        final d = _TeeDraft(t.name, holesCount);
        d.ratingCtrl.text = '${t.rating}';
        d.slopeCtrl.text = '${t.slope}';
        for (var i = 0; i < holesCount && i < t.holes.length; i++) {
          d.yards[i] = t.holes[i].yardage;
        }
        tees.add(d);
      }
      keptPhoto = edit.imagePath;
      return;
    }
    final seed = widget.initial;
    if (seed != null) {
      nameCtrl.text = seed.name;
      cityCtrl.text = seed.city;
      stateCtrl.text = seed.state;
      if (seed.scorecard.isNotEmpty) {
        holesCount = seed.scorecard.length <= 9 ? 9 : 18;
        pars = parsForHoles(seed, holesCount);
        // Tee boxes were fetched alongside the course: a rating and slope
        // decide the handicap, so an empty one would make every round
        // imported from here wrong.
        for (final t in widget.importedTees) {
          final d = _TeeDraft.fromTee(t);
          d.resize(holesCount);
          tees.add(d);
        }
        if (tees.isEmpty) tees.add(_TeeDraft('White', holesCount));
        return;
      }
    }
    pars = List.filled(holesCount, 4);
    tees.add(_TeeDraft('White', holesCount));
  }

  void _setHoles(int n) {
    setState(() {
      holesCount = n;
      pars = List.filled(n, 4);
      for (final t in tees) {
        t.resize(n);
      }
      editYardsTee = 0;
    });
  }

  void _addTee() {
    setState(() {
      final used = tees
          .map((t) => t.nameCtrl.text.trim().toLowerCase())
          .toSet();
      final next = _suggestNames.firstWhere(
        (s) => !used.contains(s.toLowerCase()),
        orElse: () => 'Tee ${tees.length + 1}',
      );
      tees.add(_TeeDraft(next, holesCount));
      editYardsTee = tees.length - 1;
    });
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    cityCtrl.dispose();
    stateCtrl.dispose();
    _photoZoom.dispose();
    for (final t in tees) {
      t.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final yardsTee = tees[editYardsTee.clamp(0, tees.length - 1)];
    final photoPath = scanPhoto?.path ?? keptPhoto;
    final showPhoto = photoPath.isNotEmpty && photoUsable(photoPath);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existing == null ? 'Add local course' : 'Edit course',
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final photoPanelHeight = (constraints.maxHeight * 0.44)
              .clamp(0.0, 300.0)
              .toDouble();
          return Column(
            children: [
              if (showPhoto)
                SizedBox(
                  key: const ValueKey('pinned-scorecard-photo'),
                  width: double.infinity,
                  height: photoPanelHeight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: _photoPreview(photoPath, isNew: scanPhoto != null),
                  ),
                ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      widget.initial != null
                          ? widget.importedTees.isNotEmpty
                                ? 'Name, place, pars, rating and slope came from the open database. Check them against the scorecard before saving — a wrong slope changes your handicap.'
                                : 'Name, place and pars came from the open database, but it had no rating or slope for this course. Copy those two from the scorecard, then save.'
                          : 'Copy par, rating and slope from the scorecard. Saved on-device, works offline.',
                    ),
                    const SizedBox(height: 8),
                    if (scanning) ...[
                      const LinearProgressIndicator(),
                      const SizedBox(height: 4),
                      Text(
                        scanStatus,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Text(
                      'Photo tips: lay the card flat, fill the frame, shoot straight-on in good light with no glare.',
                      style: AppType.meta.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: scanning ? null : _chooseScanSource,
                            icon: const Icon(Icons.document_scanner_outlined),
                            label: const Text('Scan scorecard photo'),
                          ),
                          if (lastOcrText.isNotEmpty)
                            TextButton.icon(
                              onPressed: () =>
                                  showOcrTextDialog(context, lastOcrText),
                              icon: const Icon(
                                Icons.text_snippet_outlined,
                                size: 18,
                              ),
                              label: const Text('View read text'),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Course name *',
                      ),
                    ),
                    TextField(
                      controller: cityCtrl,
                      decoration: const InputDecoration(labelText: 'City'),
                    ),
                    TextField(
                      controller: stateCtrl,
                      decoration: const InputDecoration(labelText: 'State'),
                    ),
                    Row(
                      children: [
                        const Text('Holes: '),
                        for (final n in [9, 18])
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: ChoiceChip(
                              label: Text('$n'),
                              selected: holesCount == n,
                              onSelected: (_) => _setHoles(n),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Tee boxes:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Add one per color you play. Rating/slope are required per tee — wrong values corrupt handicaps, so saving is blocked until valid.',
                      style: AppType.meta.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    for (var ti = 0; ti < tees.length; ti++)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: tees[ti].nameCtrl,
                                      decoration: InputDecoration(
                                        labelText:
                                            'Tee ${ti + 1} name / color *',
                                      ),
                                    ),
                                  ),
                                  if (tees.length > 1)
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () => setState(() {
                                        tees[ti].dispose();
                                        tees.removeAt(ti);
                                        editYardsTee = 0;
                                      }),
                                    ),
                                ],
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: tees[ti].ratingCtrl,
                                      decoration: const InputDecoration(
                                        labelText: 'Rating *',
                                      ),
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextField(
                                      controller: tees[ti].slopeCtrl,
                                      decoration: const InputDecoration(
                                        labelText: 'Slope *',
                                      ),
                                      keyboardType: TextInputType.number,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _addTee,
                        icon: const Icon(Icons.add),
                        label: const Text('Add another tee box'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Holes (par is shared by all tees):',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Tap a par to cycle 3 → 4 → 5. Tap a yardage to type it (— = unknown).',
                      style: AppType.meta.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (parFromYardages) ...[
                      Card(
                        color: Theme.of(context).colorScheme.tertiaryContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Row(
                            children: [
                              Icon(
                                Icons.help_outline,
                                size: 18,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onTertiaryContainer,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  parUncertain.isEmpty
                                      ? 'The par row was too small to read, so par was worked out from the yardages. All 18 holes look settled — give it a glance.'
                                      : 'The par row was too small to read, so par was worked out from the yardages. A par 4 and a par 5 are the same length on some holes, so check the highlighted ones (${parUncertain.join(', ')}).',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onTertiaryContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    Wrap(
                      spacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text('Yardages for: '),
                        for (var ti = 0; ti < tees.length; ti++)
                          ChoiceChip(
                            label: Text(
                              tees[ti].nameCtrl.text.trim().isEmpty
                                  ? 'Tee ${ti + 1}'
                                  : tees[ti].nameCtrl.text.trim(),
                            ),
                            selected: editYardsTee == ti,
                            onSelected: (_) =>
                                setState(() => editYardsTee = ti),
                          ),
                      ],
                    ),
                    for (var i = 0; i < holesCount; i++) _holeRow(i, yardsTee),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => _save(),
                      icon: const Icon(Icons.check),
                      label: Text(
                        widget.existing == null
                            ? 'Save course'
                            : 'Save changes',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Type an exact yardage instead of stepping.
  Future<void> _typeYards(int i, _TeeDraft t) async {
    final ctrl = TextEditingController(
      text: t.yards[i] == 0 ? '' : '${t.yards[i]}',
    );
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Hole ${i + 1} yardage'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            hintText: 'e.g. 385',
            suffixText: 'yd',
          ),
          onSubmitted: (_) =>
              Navigator.of(ctx).pop(int.tryParse(ctrl.text.trim())),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(int.tryParse(ctrl.text.trim())),
            child: const Text('Set'),
          ),
        ],
      ),
    );
    if (v != null) setState(() => t.yards[i] = v.clamp(0, 650));
  }

  /// One hole card, one uniform row: HOLE n, tap Par to cycle 3-4-5,
  /// tap the yardage to type it. Fixed height so every row is equal.
  Widget _holeRow(int i, _TeeDraft yardsTee) {
    final scheme = Theme.of(context).colorScheme;
    final yds = yardsTee.yards[i];
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              SizedBox(
                width: 62,
                child: Text(
                  'HOLE ${i + 1}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() {
                    pars[i] = pars[i] >= 5 ? 3 : pars[i] + 1;
                    // Confirming the value is the answer: stop flagging it.
                    parUncertain = {...parUncertain}..remove(i + 1);
                  }),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      decoration: parUncertain.contains(i + 1)
                          ? BoxDecoration(
                              color: scheme.tertiaryContainer,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: scheme.tertiary),
                            )
                          : null,
                      child: Text(
                        '${parUncertain.contains(i + 1) ? '? ' : ''}Par: ${pars[i]}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: parUncertain.contains(i + 1)
                              ? scheme.onTertiaryContainer
                              : scheme.primary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _typeYards(i, yardsTee),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Text(
                        yds == 0 ? '— yd' : '$yds yd',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _photoPreview(String path, {required bool isNew}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    isNew
                        ? 'Scanned photo (saves with course)'
                        : 'Saved scorecard photo',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton.icon(
                  onPressed: _removePhoto,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Remove'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          InkWell(
                            onTap: () => showCoursePhoto(
                              context,
                              nameCtrl.text.trim().isEmpty
                                  ? 'Scorecard'
                                  : nameCtrl.text.trim(),
                              path,
                            ),
                            child: _scorecardImageView(
                              path,
                              _photoZoom,
                              key: const ValueKey(
                                'course-scorecard-interactive-viewer',
                              ),
                            ),
                          ),
                          Positioned(
                            right: 8,
                            bottom: 8,
                            child: Material(
                              color: Theme.of(
                                context,
                              ).colorScheme.surface.withValues(alpha: 0.94),
                              borderRadius: BorderRadius.circular(Radii.pill),
                              elevation: 2,
                              child: _ScorecardZoomControls(
                                zoom: _photoZoom,
                                compact: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'Pinch to zoom · drag to pan · tap photo for full screen',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _removePhoto() async {
    final old = scanPhoto?.path ?? keptPhoto;
    _photoZoom.reset();
    setState(() {
      scanPhoto = null;
      keptPhoto = '';
    });
    await deleteScanPhoto(old);
  }

  Future<void> _chooseScanSource() async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (src != null) await _scanImage(src);
  }

  Future<void> _scanImage(ImageSource src) async {
    // Full resolution: downscaling destroys the small digits Tesseract
    // needs for yardages (Phase 1 of the OCR plan).
    final file = await ImagePicker().pickImage(source: src, imageQuality: 100);
    if (file == null) return;
    setState(() {
      scanning = true;
      scanStatus = 'Reading scorecard…';
    });
    try {
      // Retry ensemble: when the first read is thin, re-run OCR and merge
      // the results. Each attempt varies *preprocessing* as well as page
      // segmentation — a photo that reads badly under one preparation
      // usually reads badly under every segmentation of that same
      // preparation. Attempts are merged per field rather than ranked
      // whole, because a pass that reads every tee box but loses the small
      // print would otherwise beat the pass that got the par.
      final attempts = <ScorecardScan>[];
      final texts = <String>[];
      var bestText = '';
      ScorecardScan? bestScan;
      var attempt = 0;
      for (final variant in scanVariants) {
        if (!mounted) return;
        attempt++;
        if (attempt > 1) {
          setState(
            () => scanStatus =
                'Trying another read (${variant.label}, $attempt of ${scanVariants.length})…',
          );
        }
        final ocrPath = await preprocessScorecard(
          file.path,
          prep: variant.prep,
        );
        final attemptText = await extractScorecardText(
          ocrPath,
          args: variant.psm == null
              ? const <String, String>{}
              : <String, String>{'psm': variant.psm!},
        );
        if (attemptText.isEmpty) continue;
        final attemptScan = parseScorecardText(attemptText);
        attempts.add(attemptScan);
        texts.add(attemptText);
        // Track the best attempt by its own scan quality, so the
        // best raw text and the best scan stay consistent instead of
        // reparsing the best text on every round.
        if (bestScan == null ||
            scanQuality(attemptScan) > scanQuality(bestScan)) {
          bestScan = attemptScan;
          bestText = attemptText;
        }
        if (_scanComplete(mergeScans(attempts))) break;
      }

      if (!mounted) return;
      var scan = mergeScans(attempts);

      // Column geometry pass. The text read gives numbers in reading order,
      // so a lost digit renames every hole after it; asking for the same OCR
      // as hOCR gives each word its box, and the numbers can be put back
      // under the header's columns. It only runs when there is a reason to
      // think a value was lost, because it is another OCR call over the same
      // photo and otherwise has nothing to add.
      if (scan.tees.any((t) => t.yards.length < 18) &&
          scan.tees.any((t) => t.yards.isNotEmpty)) {
        setState(() => scanStatus = 'Realigning the table columns…');
        final geomScan = await _geometryPass(file, scan);
        if (geomScan != null && geomScan.tees.isNotEmpty) {
          attempts.add(geomScan);
          scan = mergeScans(attempts);
        }
      }
      // The par row is the smallest print on the card, so it is the first
      // thing a poor photo loses while the yardage rows survive. One extra
      // pass restricted to digits recovers it, and only runs when the normal
      // passes found no par at all.
      List<int>? digitPars;
      if (scan.pars.length != 18 && scan.pars.length != 9) {
        setState(() => scanStatus = 'Reading the par row…');
        digitPars = await _parsFromDigitsPass(file, scan);
        if (digitPars != null) {
          scan = ScorecardScan(
            pars: digitPars,
            tees: scan.tees,
            rating: scan.rating,
            slope: scan.slope,
            hcp: scan.hcp,
            parSubtotals: const SubtotalCheck(
              front: true,
              back: null,
              total: true,
              printed: false,
            ),
          );
          texts.add(lastOcrDigitsText);
        }
      }
      if (!mounted) return;
      _applyScan(scan, file, bestText, texts);
    } on ScanException catch (e) {
      if (!mounted) return;
      setState(() => scanning = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// The hOCR pass: re-reads the photo asking for word boxes and places each
  /// tee box's yardages under the hole columns. Returns null when the
  /// platform has no hOCR or the pass found no table to align to, in which
  /// case the text read stands on its own.
  Future<ScorecardScan?> _geometryPass(
    XFile file,
    ScorecardScan textScan,
  ) async {
    try {
      final path = await preprocessScorecard(
        file.path,
        prep: ImagePrep.stretched,
      );
      final hocr = await extractScorecardHocr(path);
      if (hocr == null) return null;
      lastOcrHocrText = hocr;
      final geom = parseHocrGeometry(hocr, textScan: textScan);
      return geom.tees.isEmpty ? null : geom;
    } catch (_) {
      return null;
    }
  }

  /// One extra OCR pass restricted to digits, used only to recover the par
  /// row. Returns null when the pass yields no par row that adds up.
  ///
  /// Runs on the stretched image, which keeps the grey levels Tesseract
  /// needs: a binarized pass turns a thin digit into a shape it is happy to
  /// call a letter even with a whitelist.
  Future<List<int>?> _parsFromDigitsPass(XFile file, ScorecardScan scan) async {
    try {
      final path = await preprocessScorecard(
        file.path,
        prep: ImagePrep.stretched,
      );
      final text = await extractScorecardText(path, args: digitsOnlyArgs);
      if (text.trim().isEmpty) return null;
      lastOcrDigitsText = text;
      final total = printedParTotal(text);
      // The digits pass has no labels, so the par row is recognised by its
      // shape instead: a run of 18 values in 3..5. The printed total, when
      // the card gave one, is what makes a match certain — a run of single
      // digits that adds up to the total next to it is not a coincidence.
      for (final line in text.split('\n')) {
        final row = [
          for (final n in RegExp(
            r'\d+',
          ).allMatches(line).map((m) => int.parse(m.group(0)!)))
            if (n >= 3 && n <= 5) n,
        ];
        if (row.length != 18) continue;
        final sum = row.fold(0, (a, b) => a + b);
        if (total != null && sum != total) continue;
        if (total == null && sum < 54) continue;
        return row;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// True when a scan has nothing left worth another OCR pass: all three
  /// kinds of data the card carries, and nothing that failed validation.
  static bool _scanComplete(ScorecardScan s) {
    if (s.pars.length != 18 && s.pars.length != 9) return false;
    if (s.tees.isEmpty || s.tees.every((t) => t.yards.length < 18)) {
      return false;
    }
    if (!validStrokeIndexes(s.hcp, s.pars.length)) return false;
    if (s.parSubtotals.printed && !s.parSubtotals.ok) return false;
    return s.tees.every((t) => t.verified);
  }

  /// Prefills the form from a scan. OCR guesses — the user verifies
  /// everything before saving. The photo is kept and stored with the
  /// course on save so it can be viewed later.
  void _applyScan(
    ScorecardScan scan,
    XFile file,
    String rawText, [
    List<String> allTexts = const [],
  ]) {
    final filled = <String>[];
    setState(() {
      scanning = false;
      scanPhoto = file;
      _photoZoom.reset();
      lastOcrText = rawText;
      lastOcrAttempts = List.of(allTexts);
      scanHcp = const [];
      parUncertain = const {};
      parFromYardages = false;
      if (scan.pars.length == 18 || scan.pars.length == 9) {
        holesCount = scan.pars.length;
        pars = List.of(scan.pars);
        filled.add('${scan.pars.length} pars');
      } else {
        // The digits pass already ran and came back empty, so par has to be
        // worked out from the yardages: the yardage rows are repeated once
        // per tee box and usually survive a photo that lost the par row. A
        // hole that is short from every tee box is a par 3 whatever the par
        // row said. Holes whose length cannot separate a par 4 from a par 5
        // are flagged for the user rather than guessed silently.
        final proposal = inferParFromYardages([
          for (final t in scan.tees)
            if (t.verified) t.yards,
        ], total: printedParTotal(rawText));
        if (proposal != null) {
          holesCount = 18;
          pars = List.of(proposal.pars);
          parUncertain = proposal.uncertainHoles.toSet();
          parFromYardages = true;
          filled.add('par from yardages');
        }
      }
      if (scan.tees.isNotEmpty) {
        for (final t in tees) {
          t.dispose();
        }
        tees.clear();
        for (final st in scan.tees) {
          final d = _TeeDraft(st.name, holesCount);
          for (var i = 0; i < holesCount && i < st.yards.length; i++) {
            d.yards[i] = st.yards[i];
          }
          tees.add(d);
        }
        editYardsTee = 0;
        filled.add(
          '${scan.tees.length} tee${scan.tees.length == 1 ? '' : 's'}',
        );
      } else {
        for (final t in tees) {
          t.resize(holesCount);
        }
      }
      // Every tee box carries its own rating/slope on the card; fall back to
      // the card-wide value for the first tee only, since one rating cannot
      // describe five different tees.
      for (var i = 0; i < tees.length; i++) {
        final st = i < scan.tees.length ? scan.tees[i] : null;
        final d = tees[i];
        final r = st?.rating ?? (i == 0 ? scan.rating : null);
        final s = st?.slope ?? (i == 0 ? scan.slope : null);
        if (r != null && d.ratingCtrl.text.trim().isEmpty) {
          d.ratingCtrl.text = r.toString();
        }
        if (s != null && d.slopeCtrl.text.trim().isEmpty) {
          d.slopeCtrl.text = s.toString();
        }
      }
      if (tees.isNotEmpty) {
        if (tees.first.ratingCtrl.text.trim().isNotEmpty) filled.add('rating');
        if (tees.first.slopeCtrl.text.trim().isNotEmpty) filled.add('slope');
      }
      // A scanned handicap row is the real stroke index, so it beats the
      // odd/even estimate: it decides which holes a handicap is applied to.
      if (validStrokeIndexes(scan.hcp, holesCount)) {
        scanHcp = List.of(scan.hcp);
        filled.add('handicap');
      }
    });
    // Say what the card itself confirms. A row that agrees with its printed
    // OUT/IN/TOT is far more trustworthy than one that does not, so the
    // user knows which tee boxes to re-read before saving.
    final notes = <String>[];
    if (scan.pars.isNotEmpty) {
      if (scan.parSubtotals.printed) {
        notes.add(
          scan.parSubtotals.ok
              ? 'par matches the printed totals'
              : 'par does NOT match the printed totals',
        );
      }
    }
    if (scan.tees.isNotEmpty) {
      final verified = scan.verifiedTees;
      if (verified > 0) {
        notes.add('$verified/${scan.tees.length} tees match printed totals');
      }
      final mismatched = [
        for (final t in scan.tees)
          if (t.parMismatch.isNotEmpty)
            '${t.name} hole ${t.parMismatch.join(",")}',
      ];
      if (mismatched.isNotEmpty) {
        notes.add('check yardage vs par on ${mismatched.join("; ")}');
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          [
            if (filled.isEmpty)
              'Could not read a scorecard from that photo — try closer, straight-on, well-lit. The form is unchanged.'
            else
              'Scan filled in ${filled.join(', ')}. Check every value before saving.',
            if (notes.isNotEmpty) notes.join(' · '),
          ].join('\n'),
        ),
        duration: const Duration(seconds: 7),
      ),
    );
  }

  Future<void> _save() async {
    final name = nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Give the course a name first.')),
      );
      return;
    }
    final seenNames = <String>{};
    for (var ti = 0; ti < tees.length; ti++) {
      final t = tees[ti];
      final tName = t.nameCtrl.text.trim();
      if (tName.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Name tee ${ti + 1} (e.g. Blue, White, Red).'),
          ),
        );
        return;
      }
      if (!seenNames.add(tName.toLowerCase())) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Two tees are both named "$tName".')),
        );
        return;
      }
      final rating = double.tryParse(t.ratingCtrl.text.trim());
      final slope = int.tryParse(t.slopeCtrl.text.trim());
      if (rating == null || rating < 55 || rating > 85) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Enter the course rating for "$tName" from the scorecard (e.g. 71.2).',
            ),
          ),
        );
        return;
      }
      if (slope == null || slope < 55 || slope > 155) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Enter the slope for "$tName" from the scorecard (55–155).',
            ),
          ),
        );
        return;
      }
    }
    final id =
        widget.existing?.id ??
        'custom-${DateTime.now().microsecondsSinceEpoch}';
    String slug(String s) => s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    String imagePath = keptPhoto;
    if (scanPhoto != null) {
      try {
        imagePath = await persistScanPhoto(scanPhoto!, id);
      } catch (_) {
        imagePath = keptPhoto;
      }
    }
    if (!mounted) return;
    // Stroke index comes off the card's handicap row when the scan read
    // one; otherwise it is estimated (odd front / even back), which the
    // form does not ask for.
    final siRow = validStrokeIndexes(scanHcp, holesCount)
        ? List<int>.of(scanHcp)
        : estimateStrokeIndexes(holesCount);
    Navigator.of(context).pop(
      Course(
        id: id,
        name: name,
        city: cityCtrl.text.trim(),
        state: stateCtrl.text.trim(),
        tees: [
          for (var ti = 0; ti < tees.length; ti++)
            Tee(
              id: '$id-${slug(tees[ti].nameCtrl.text.trim())}-$ti',
              name: tees[ti].nameCtrl.text.trim(),
              rating: double.parse(tees[ti].ratingCtrl.text.trim()),
              slope: int.parse(tees[ti].slopeCtrl.text.trim()),
              holes: List.generate(
                holesCount,
                (i) => HoleInfo(
                  number: i + 1,
                  par: pars[i],
                  yardage: tees[ti].yards[i],
                  strokeIndex: siRow[i],
                ),
              ),
            ),
        ],
        custom: true,
        imagePath: imagePath,
        ocrText: lastOcrText,
        ocrAttempts: lastOcrAttempts,
      ),
    );
  }
}

// ---------------- STATS ----------------
class StatsPage extends StatelessWidget {
  final GolfStore store;
  const StatsPage({super.key, required this.store});
  @override
  Widget build(BuildContext context) {
    final s = store.statSummary();
    return Scaffold(
      appBar: AppBar(title: const Text('Performance')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'ROUND BY ROUND',
            style: AppType.meta.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              letterSpacing: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          if (s.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Icon(
                      Icons.insights_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Post a round to see FIR, GIR, putts and penalties.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (s.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _stat(context, 'FIR %', s['FIR']!),
                _stat(context, 'GIR %', s['GIR']!),
                _stat(context, 'Putts/hole', s['Putts/Hole']!),
                _stat(context, 'Pen/round', s['Pen/Round']!),
              ],
            ),
          const SizedBox(height: 24),
          Text('By round', style: Theme.of(context).textTheme.titleMedium),
          for (final r in store.rounds)
            Card(
              margin: const EdgeInsets.only(top: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primaryContainer,
                  foregroundColor: Theme.of(
                    context,
                  ).colorScheme.onPrimaryContainer,
                  child: Text(
                    '${r.totalGross}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                title: Text(courseName(store, r)),
                subtitle: Text(
                  'Putts ${r.totalPutts} • Pen ${r.totalPenalties} • '
                  'CH ${r.courseHandicap ?? '—'}',
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, String k, double v) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(
              k,
              style: AppType.meta.copyWith(color: scheme.onSurfaceVariant),
            ),
            Text(
              v.toStringAsFixed(1),
              style: AppType.title.copyWith(fontSize: 22),
            ),
          ],
        ),
      ),
    );
  }
}

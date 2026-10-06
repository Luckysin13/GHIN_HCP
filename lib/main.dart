import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_theme.dart';
import 'csv_import.dart';
import 'course_catalog.dart';
import 'design_tokens.dart';
import 'ghin_brand_mark.dart';
import 'handicap_card.dart';
import 'recent_rounds_section.dart';
import 'models.dart';
import 'quick_post.dart';
import 'score_entry.dart';
import 'scan_service.dart';
import 'scorecard_scan.dart';
import 'opengolf.dart';
import 'photo_source_sheet.dart';
import 'playing_handicap_panel.dart';
import 'export.dart';
import 'export_io.dart';
import 'store.dart';
import 'whs.dart' as whs;
import 'theme_toggle.dart';
import 'table_geometry.dart';

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
      body: IndexedStack(index: idx, children: pages),
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
            onSelected: (v) {
              if (v == 'csv' || v == 'json') {
                _runExport(context, store, v);
              }
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
              PopupMenuItem(
                value: 'import',
                child: ListTile(
                  leading: Icon(Icons.restore),
                  title: Text('Import backup'),
                  subtitle: Text('Restore a JSON backup'),
                ),
                onTap: () => _runImport(context, store),
              ),
              PopupMenuItem(
                value: 'import-csv',
                child: ListTile(
                  leading: Icon(Icons.table_view),
                  title: Text('Import CSV'),
                  subtitle: Text('Bring rounds in from a spreadsheet'),
                ),
                onTap: () => _runImportCsv(context, store),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(Insets.gutter),
        children: [
          HandicapCard(index: hi, roundCount: rounds.length, pending: pending),
          const SizedBox(height: Insets.md),
          QuickPostCard(store: store),
          const SizedBox(height: Insets.md),
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

/// Deletes a round and gives four seconds to bring it back: a delete on a
/// phone is one mis-tap away from losing a round for good, so the toast's
/// 4s window is the safety net. Only an actual dismissal finalizes the
/// delete (and the scorecard photo goes with it); Undo keeps everything.
void _deleteRound(BuildContext context, GolfStore store, Round r) {
  final messenger = ScaffoldMessenger.of(context);
  final removed = store.deleteRound(r.id);
  if (removed == null) return;
  messenger.hideCurrentSnackBar();
  final photoPath = removed.round.imagePath;
  messenger
      .showSnackBar(
        SnackBar(
          content: Text(
            'Deleted ${courseName(store, removed.round)} • ${removed.round.totalGross}',
          ),
          duration: const Duration(seconds: 4),
          // A snackbar with an action defaults to `persist` in recent Flutter
          // versions, which pins it on screen forever instead of timing out.
          // The undo toast must be the exception: 4 seconds to undo, then it
          // goes away and the delete is final.
          persist: false,
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => store.restoreRound(removed.round, removed.index),
          ),
        ),
      )
      .closed
      .then((reason) {
        // Undo keeps the round, so it keeps the photo; any other dismissal
        // finalizes the delete and the orphaned file goes with it.
        if (reason != SnackBarClosedReason.action && photoPath.isNotEmpty) {
          deleteScanPhoto(photoPath);
        }
      });
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
  if (nothingNew && backup.rounds.isEmpty) {
    messenger.showSnackBar(
      SnackBar(content: Text(_nothingNewMessage(backup, p))),
    );
    return;
  }

  if (!context.mounted) return;
  final RoundImportMode? roundsMode;
  if (backup.rounds.isNotEmpty) {
    roundsMode = await showDialog<RoundImportMode>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore backup?'),
        content: Text(
          '${_restoreSummary(p)}\n\n'
          'Merge keeps saved rounds and adds missing rounds. '
          'Overwrite replaces all saved rounds with the rounds in this file.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, RoundImportMode.overwrite),
            child: const Text('Overwrite saved rounds'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, RoundImportMode.merge),
            child: const Text('Merge'),
          ),
        ],
      ),
    );
    if (roundsMode == null) return;
  } else {
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
    roundsMode = RoundImportMode.merge;
  }

  final r = await store.importBackup(backup, roundsMode: roundsMode);
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
  final overwritePreview = store.previewCsv(
    rows,
    roundsMode: RoundImportMode.overwrite,
  );

  if (!context.mounted) return;
  final roundsMode = await showDialog<RoundImportMode>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Import CSV?'),
      content: Text(
        '${_csvSummary(p)}\n\n'
        'Merge keeps saved rounds and adds missing rounds. '
        'Overwrite replaces all saved rounds with '
        '${_plural(overwritePreview.roundsAdded, 'round')} from this file.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(ctx).colorScheme.error,
          ),
          onPressed: () => Navigator.pop(ctx, RoundImportMode.overwrite),
          child: const Text('Overwrite saved rounds'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, RoundImportMode.merge),
          child: const Text('Merge'),
        ),
      ],
    ),
  );
  if (roundsMode == null) return;

  final r = store.importCsv(rows, roundsMode: roundsMode);
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
      'Existing courses are left alone; backup settings are restored '
      'when they differ.';
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

// ---------------- POST ----------------

/// Black or white text for [background], whichever reads better.
Color _readableOn(Color background) =>
    background.computeLuminance() > 0.179 ? Colors.black : Colors.white;

/// One quick-entry score button: a fixed-height oval pill with a centered
/// label. Custom-built instead of a ChoiceChip so all six pills render
/// identical geometry: same box, same 2px outline, same text position.
class ScorePill extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const ScorePill({
    super.key,
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 24,
      child: Material(
        shape: StadiumBorder(
          side: BorderSide(width: 2, color: color.withValues(alpha: 0.9)),
        ),
        color: selected ? color : color.withValues(alpha: 0.35),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? _readableOn(color) : scheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Typed score entry for one hole, for scores past triple bogey.
class _HoleScoreDialog extends StatefulWidget {
  final int holeNumber;
  final int par;
  final int currentScore;

  const _HoleScoreDialog({
    required this.holeNumber,
    required this.par,
    required this.currentScore,
  });

  @override
  State<_HoleScoreDialog> createState() => _HoleScoreDialogState();
}

class _HoleScoreDialogState extends State<_HoleScoreDialog> {
  late final TextEditingController _ctrl = TextEditingController(
    text: '${widget.currentScore}',
  );
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = int.tryParse(_ctrl.text.trim());
    if (v == null || v < minHoleScore || v > maxHoleScore) {
      setState(
        () => _error = 'Enter a score from $minHoleScore to $maxHoleScore.',
      );
      return;
    }
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Hole ${widget.holeNumber}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Par ${widget.par} — triple is ${widget.par + 3}.'),
          const SizedBox(height: 8),
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: 'Score', errorText: _error),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

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
  String _photoPath = '';
  // A scorecard picture taken mid-round, persisted once the round is saved.
  XFile? _pendingPhoto;
  // Playing Conditions Calculation adjustment already applied by the venue to
  // this round. Null-player/direct-entry screens can leave it at 0.0.
  double _pcc = 0.0;
  final _stripCtrl = ScrollController();
  final _pageCtrl = ScrollController();
  double _stripW = 0;

  @override
  void dispose() {
    _stripCtrl.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }

  /// Keeps the selected hole chip centered in the strip after it moves.
  void _centerSelSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_stripCtrl.hasClients || holes.isEmpty || _stripW <= 0) return;
      const itemW = 60.0; // 54 chip + 6 separator
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

  /// Typed entry for scores past triple, via the hole header.
  Future<void> _editHoleScore(int i) async {
    final entered = await showDialog<int>(
      context: context,
      builder: (_) => _HoleScoreDialog(
        holeNumber: i + 1,
        par: _parAt(i, _tee()),
        currentScore: holes[i].score,
      ),
    );
    if (entered == null || !mounted) return;
    _setScore(i, entered);
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
    _photoPath = existing?.imagePath ?? '';
    _pcc = existing?.pcc ?? 0.0;
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
      final firstCourse = widget.store.alphabeticalCourses.first;
      courseId = firstCourse.id;
      teeId = firstCourse.defaultTee.id;
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

  /// Unrounded Course Handicap for the current selection, using the live
  /// Handicap Index (the number a player plans their round against). Null
  /// until a Handicap Index exists or the tee cannot rate the selection.
  double? unroundedChForPanel(Tee? tee) {
    final index = widget.store.handicapIndex;
    if (tee == null || index == null) return null;
    return tee.unroundedCourseHandicapForRound(
      holesPlayed: holesCount,
      startHole: startHole,
      handicapIndex: index,
    );
  }

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
    final courses = widget.store.alphabeticalCourses;
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
    // The dropdown must contain the current count: a legacy partial round
    // keeps its own count in the edit form, while a fresh card clamps to a
    // supported count (preferring 18) and rebuilds its scores from par.
    var holeOptions = holeCountOptionsForTee(holeCountTee.holes.length);
    if (editing && !holeOptions.contains(holesCount)) {
      holeOptions = [...holeOptions, holesCount]..sort();
    }
    if (!editing && !holeOptions.contains(holesCount)) {
      holesCount = holeOptions.last;
      holes = List.generate(holesCount, (i) => HoleScore(score: _parFor(i)));
    }
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
        key: const ValueKey('play-page-list'),
        controller: _pageCtrl,
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
                    decoration: const InputDecoration(labelText: 'Teebox'),
                    items: [
                      for (final t in course.tees)
                        DropdownMenuItem(
                          value: t.id,
                          child: Text(
                            '${t.name} • ${t.rating}/${t.slope} • Par ${t.par}',
                          ),
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
                      for (final n in holeOptions)
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
                  const SizedBox(height: 8),
                  DropdownButtonFormField<double>(
                    key: const ValueKey('play-pcc-selector'),
                    initialValue: _pcc,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'PCC (venue adjustment)',
                    ),
                    items: [
                      for (final value in pccOptions)
                        DropdownMenuItem(
                          value: value,
                          child: Text(
                            value == 0.0
                                ? 'None'
                                : '${value >= 0 ? "+" : ""}${value.toStringAsFixed(1)}',
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => _pcc = v ?? 0.0),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          LayoutBuilder(
            builder: (ctx, cons) {
              _stripW = cons.maxWidth;
              return SizedBox(
                height: 78,
                child: ListView.separated(
                  controller: _stripCtrl,
                  scrollDirection: Axis.horizontal,
                  itemCount: holes.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (ctx, i) {
                    final par = _parAt(i, tee);
                    final active = i == sel;
                    final col = _scoreColor(context, holes[i].score, par);
                    final scheme = Theme.of(ctx).colorScheme;
                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _selectHole(i),
                      child: Container(
                        key: ValueKey('play-hole-chip-$i'),
                        width: 54,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: active
                              ? Border.all(color: scheme.primary, width: 3)
                              : Border.all(color: scheme.outlineVariant),
                          boxShadow: active
                              ? [
                                  BoxShadow(
                                    color: scheme.primary.withValues(
                                      alpha: 0.24,
                                    ),
                                    blurRadius: 6,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : null,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(9),
                          child: Column(
                            children: [
                              Expanded(
                                child: Container(
                                  key: ValueKey('play-hole-number-$i'),
                                  width: double.infinity,
                                  color: scheme.primaryContainer,
                                  alignment: Alignment.center,
                                  child: Text(
                                    '${i + 1}',
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700,
                                      color: scheme.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Container(
                                  key: ValueKey('play-hole-score-$i'),
                                  width: double.infinity,
                                  color: col,
                                  alignment: Alignment.center,
                                  child: Text(
                                    '${holes[i].score}',
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: _readableOn(col),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
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
          if (editing) ...[
            const SizedBox(height: Insets.md),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: photoUsable(_photoPath)
                    ? Row(
                        children: [
                          InkWell(
                            onTap: () => showCoursePhoto(
                              context,
                              course.name,
                              _photoPath,
                            ),
                            child: _roundPhotoThumb(_photoPath),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text('Scorecard photo attached'),
                          ),
                          TextButton.icon(
                            key: const ValueKey('edit-round-remove-photo'),
                            onPressed: _removeRoundPhoto,
                            icon: const Icon(Icons.delete_outline, size: 18),
                            label: const Text('Remove'),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          const Expanded(child: Text('No scorecard photo')),
                          OutlinedButton.icon(
                            key: const ValueKey('edit-round-add-photo'),
                            onPressed: _pickRoundPhoto,
                            icon: const Icon(Icons.add_a_photo_outlined),
                            label: const Text('Save Scorecard'),
                          ),
                        ],
                      ),
              ),
            ),
          ],
          if (!editing) ...[
            const SizedBox(height: Insets.md),
            OutlinedButton.icon(
              key: const ValueKey('play-save-scorecard'),
              onPressed: _pickPlayPhoto,
              icon: Icon(
                _pendingPhoto == null
                    ? Icons.add_a_photo_outlined
                    : Icons.check_circle_outline,
              ),
              label: Text(
                _pendingPhoto == null ? 'Save Scorecard' : 'Attached',
              ),
            ),
            const SizedBox(height: Insets.md),
          ],
          FilledButton.icon(
            icon: const Icon(Icons.check),
            label: Text(
              editing
                  ? 'Update ${holes.fold(0, (s, h) => s + h.score)} total'
                  : 'Save ${holes.fold(0, (s, h) => s + h.score)} total',
            ),
            onPressed: _save,
          ),
          const SizedBox(height: Insets.md),
          PlayingHandicapPanel(
            unroundedCourseHandicap: unroundedChForPanel(tee),
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
                  child: InkWell(
                    key: const ValueKey('play-hole-header'),
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _editHoleScore(i),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'Hole ${i + 1}',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          TextSpan(
                            text: ' • Par $par',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
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
            // Fixed three-per-row grid: every pill stretches to the same
            // width instead of shrink-wrapping its label.
            Column(
              children: [
                for (var r = 0; r < quick.length; r += 3)
                  Padding(
                    padding: EdgeInsets.only(top: r == 0 ? 0 : 6),
                    child: Row(
                      children: [
                        for (final (c, (d, label))
                            in quick.skip(r).take(3).indexed) ...[
                          if (c > 0) const SizedBox(width: 6),
                          Expanded(
                            child: ScorePill(
                              label: label,
                              selected: h.score == (par + d).clamp(1, 12),
                              color: _diffColor(d),
                              onTap: () => _setScore(i, par + d, advance: true),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
            // Breathe the same amount below the pills as above them.
            const SizedBox(height: 8),
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

  Widget _roundPhotoThumb(String path) => ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: SizedBox(
      width: 56,
      height: 56,
      child: kIsWeb
          ? Image.network(path, fit: BoxFit.cover)
          : Image.file(File(path), fit: BoxFit.cover),
    ),
  );

  Future<void> _pickRoundPhoto() async {
    final existing = widget.existing;
    if (existing == null) return;
    final result = await pickScorecardPhoto(
      context,
      showRemove: _photoPath.isNotEmpty,
    );
    switch (result) {
      case null:
        return;
      case PhotoRemoved():
        await _removeRoundPhoto();
      case PhotoPicked(:final file):
        final path = await persistRoundPhoto(file, existing.id);
        if (!mounted) return;
        setState(() => _photoPath = path);
    }
  }

  Future<void> _removeRoundPhoto() async {
    final old = _photoPath;
    setState(() => _photoPath = '');
    await deleteScanPhoto(old);
  }

  Future<void> _pickPlayPhoto() async {
    final result = await pickScorecardPhoto(
      context,
      showRemove: _pendingPhoto != null,
    );
    switch (result) {
      case null:
        return;
      case PhotoRemoved():
        setState(() => _pendingPhoto = null);
      case PhotoPicked(:final file):
        setState(() => _pendingPhoto = file);
    }
  }

  Future<void> _save() async {
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
    final ch = hi == null
        ? existing?.courseHandicap
        : tee.courseHandicapForRound(
                holesPlayed: holes.length,
                startHole: startHole,
                handicapIndex: hi,
              ) ??
              existing?.courseHandicap;
    // Posting caps (net double bogey, or par + 5 while establishing) apply
    // to the stored card; live entry keeps the actual scores until now.
    final adjustment = adjustScoresForPosting(
      handicapIndex: hi,
      courseHandicap: ch ?? 0,
      holes: [
        for (var i = 0; i < holes.length; i++)
          (
            par: tee.holes[startHole + i].par,
            // A hole with no published index ranks below every ranked hole.
            strokeIndex: tee.holes[startHole + i].strokeIndex ?? 19,
            grossScore: holes[i].score,
          ),
      ],
    );
    for (var i = 0; i < holes.length; i++) {
      holes[i].score = adjustment.holes[i].adjustedScore;
      holes[i].sanitize();
    }
    final id = existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
    var imagePath = _photoPath;
    final pending = existing == null ? _pendingPhoto : null;
    if (pending != null) {
      try {
        imagePath = await persistRoundPhoto(pending, id);
      } catch (_) {
        // The round matters more than its picture.
      }
      if (!mounted) return;
    }
    final r = Round(
      // An edit keeps the round identity and playing-handicap snapshot, while
      // allowing the recorded play date to be corrected.
      id: id,
      courseId: courseId!,
      teeId: teeId!,
      playedAt: playedAt,
      format: existing?.format ?? 'stroke',
      isTournament: existing?.isTournament ?? false,
      holes: holes,
      pcc: _pcc,
      incompleteRoundReasonValid: incompleteRoundReasonValid,
      courseHandicap: ch,
      handicapIndexAtPlay: hi,
      startHole: startHole,
      imagePath: imagePath,
    );
    if (existing != null) {
      widget.store.updateRound(r);
    } else {
      widget.store.addRound(r);
    }
    final capped = adjustment.cappedCount;
    final cappedNote = capped == 0
        ? ''
        : ' $capped ${capped == 1 ? 'hole' : 'holes'} capped at max.';
    final verb = existing != null ? 'Updated' : 'Saved';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$verb ${r.totalGross} (CH ${ch ?? '—'}) — '
          '${selectionLabel(holes.length, startHole)}.$cappedNote',
        ),
      ),
    );
    if (existing != null) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      // Fresh card for the next round: same course, scores back to par,
      // hole 1 selected and scrolled into view.
      _pendingPhoto = null;
      _resetScores();
      _centerSelSoon();
      if (_pageCtrl.hasClients) {
        _pageCtrl.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    }
  }
}

/// Full-screen viewer for a saved scorecard photo.
///
/// [onDelete] adds a delete button to the app bar; it runs after the viewer
/// pops itself, and is null where the photo is view-only.
void showCoursePhoto(
  BuildContext context,
  String courseName,
  String path, {
  Future<void> Function()? onDelete,
}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => _CoursePhotoViewer(
        courseName: courseName,
        path: path,
        onDelete: onDelete,
      ),
    ),
  );
}

class _CoursePhotoViewer extends StatefulWidget {
  final String courseName;
  final String path;
  final Future<void> Function()? onDelete;

  const _CoursePhotoViewer({
    required this.courseName,
    required this.path,
    this.onDelete,
  });

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
    final onDelete = widget.onDelete;
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.courseName} — scorecard'),
        actions: [
          if (onDelete != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete photo',
              onPressed: () async {
                Navigator.of(context).pop();
                await onDelete();
              },
            ),
        ],
      ),
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
    required int startHole,
  }) {
    final heads = <String>[outHead];
    if (inHead != null) heads.add(inHead);
    final ratings = tee.nineHoleRatings(startHole);
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
          padding: const EdgeInsets.only(top: 8, bottom: 2),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 2,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              if (ratings != null)
                Text(
                  'RATING ${ratings.rating.toStringAsFixed(1)}  •  SLOPE ${ratings.slope}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.25,
                    color: theme.fg.withValues(alpha: 0.72),
                  ),
                ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            horizontalMargin: 2,
            columnSpacing: 2,
            headingRowHeight: 30,
            dataRowMinHeight: 27,
            dataRowMaxHeight: 29,
            dividerThickness: 0.5,
            showCheckboxColumn: false,
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
                  width: 44,
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
                    width: 38,
                    last: k == lastHead,
                    style: headStyle.copyWith(color: theme.fg),
                  ),
                ),
            ],
            rows: [
              DataRow(
                cells: [
                  DataCell(cell('HCP', dataBorder, width: 44, style: boldData)),
                  for (var k = 0; k < hs.length; k++)
                    DataCell(
                      cell(
                        hs[k].strokeIndex?.toString() ?? '-',
                        dataBorder,
                        style: dataStyle,
                      ),
                    ),
                  for (var k = 0; k < heads.length; k++)
                    DataCell(
                      cell(
                        '—',
                        dataBorder,
                        width: 38,
                        last: k == lastHead,
                        style: dataStyle,
                      ),
                    ),
                ],
              ),
              DataRow(
                cells: [
                  DataCell(cell('Par', dataBorder, width: 44, style: boldData)),
                  for (var k = 0; k < hs.length; k++)
                    DataCell(
                      cell('${hs[k].par}', dataBorder, style: dataStyle),
                    ),
                  DataCell(
                    cell(
                      '${parSum(hs)}',
                      dataBorder,
                      width: 38,
                      last: inHead == null,
                      style: boldData,
                    ),
                  ),
                  if (inHead != null)
                    DataCell(
                      cell(
                        '$totPar',
                        dataBorder,
                        width: 38,
                        last: true,
                        style: boldData,
                      ),
                    ),
                ],
              ),
              DataRow(
                cells: [
                  DataCell(cell('Yds', dataBorder, width: 44, style: boldData)),
                  for (var k = 0; k < hs.length; k++)
                    DataCell(
                      cell(yds(hs[k].yardage), dataBorder, style: dataStyle),
                    ),
                  DataCell(
                    cell(
                      yds(ydsSum(hs)),
                      dataBorder,
                      width: 38,
                      last: inHead == null,
                      style: boldData,
                    ),
                  ),
                  if (inHead != null)
                    DataCell(
                      cell(
                        yds(totYds ?? 0),
                        dataBorder,
                        width: 38,
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
      nine('FRONT 9', front, 'OUT', startHole: 0),
      if (back.isNotEmpty)
        nine(
          'BACK 9',
          back,
          'IN',
          inHead: 'TOT',
          totPar: parSum(tee.holes),
          totYds: ydsSum(tee.holes),
          startHole: 9,
        ),
    ],
  );
}

// ---------------- COURSES ----------------
class CoursesPage extends StatefulWidget {
  final GolfStore store;
  final CourseRatingCatalog? catalog;
  final OpenGolfApi? openGolfApi;
  const CoursesPage({
    super.key,
    required this.store,
    this.catalog,
    this.openGolfApi,
  });
  @override
  State<CoursesPage> createState() => _CoursesPageState();
}

class _CoursesPageState extends State<CoursesPage> {
  /// Past this many saved courses the card list collapses into a dropdown.
  static const _savedCourseDropdownThreshold = 5;

  String q = '';
  String? selectedCourseId;
  String? selectedTeeId;
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  CourseRatingCatalog? _courseCatalog;
  String? _courseCatalogError;
  late final OpenGolfApi _openGolfApi = widget.openGolfApi ?? OpenGolfApi();
  final Set<String> _loadingCatalogCourses = {};

  @override
  void initState() {
    super.initState();
    final catalog = widget.catalog;
    if (catalog == null) {
      _loadCourseCatalog();
    } else {
      _courseCatalog = catalog;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    if (widget.openGolfApi == null) _openGolfApi.close();
    super.dispose();
  }

  Future<void> _loadCourseCatalog() async {
    try {
      final catalog = await CourseRatingCatalog.load();
      if (mounted) setState(() => _courseCatalog = catalog);
    } catch (error) {
      if (mounted) setState(() => _courseCatalogError = '$error');
    }
  }

  void _onSearchChanged(String v) {
    setState(() => q = v);
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final local = store.searchCourses(q);
    final catalogMatches = q.trim().length >= 2
        ? (_courseCatalog?.search(q) ?? const <CourseCatalogCourse>[])
        : const <CourseCatalogCourse>[];
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
    String teeLabel(Tee t) =>
        '${t.name} • ${t.rating}/${t.slope} • Par ${t.par}';

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
              hintText: 'Search Courses',
            ),
            onChanged: _onSearchChanged,
          ),
          if (q.trim().length >= 2) ...[
            const SizedBox(height: 4),
            Text(
              'LOCAL COURSE RATINGS',
              style: AppType.meta.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (_courseCatalog == null && _courseCatalogError == null)
              const LinearProgressIndicator(),
            if (_courseCatalogError != null)
              Text(
                'Course catalog unavailable: $_courseCatalogError',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_courseCatalog != null && catalogMatches.isEmpty)
              Text(
                'No course-rating matches.',
                style: AppType.meta.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            if (catalogMatches.length == 15)
              Text(
                'Showing up to 15 matches. Add a city or course name to narrow results.',
                style: AppType.meta.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            for (final c in catalogMatches)
              Card(
                margin: const EdgeInsets.only(top: Insets.sm),
                child: ListTile(
                  leading: const Icon(Icons.storage_outlined),
                  title: Text(c.name),
                  subtitle: Text(
                    [
                      [
                        c.city,
                        c.state,
                      ].where((part) => part.isNotEmpty).join(', '),
                      'USGA course ID ${c.sourceId}',
                    ].where((part) => part.isNotEmpty).join(' • '),
                  ),
                  trailing: TextButton(
                    onPressed: _loadingCatalogCourses.contains(c.appCourseId)
                        ? null
                        : () => _openCatalogCourse(c),
                    child: _loadingCatalogCourses.contains(c.appCourseId)
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            widget.store.courseById(c.appCourseId) == null
                                ? 'Import'
                                : 'Update course',
                          ),
                  ),
                  onTap: () => _openCatalogCourse(c),
                ),
              ),
            const SizedBox(height: 4),
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
          if (local.isNotEmpty &&
              store.courses.length > _savedCourseDropdownThreshold)
            _savedCourseDropdown(context, local, course)
          else
            for (final c in local)
              Card(
                margin: const EdgeInsets.only(top: Insets.xs),
                color: c.id == selectedCourseId
                    ? Theme.of(context).colorScheme.primaryContainer
                    : null,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: Insets.sm,
                  ),
                  selected: c.id == selectedCourseId,
                  selectedColor: Theme.of(
                    context,
                  ).colorScheme.onPrimaryContainer,
                  leading: Icon(
                    c.id == selectedCourseId
                        ? Icons.golf_course
                        : Icons.golf_course_outlined,
                    color: c.id == selectedCourseId
                        ? Theme.of(context).colorScheme.onPrimaryContainer
                        : Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(c.name, key: ValueKey('course-name-${c.id}')),
                  subtitle: Text(
                    [
                      // A scanned card does not always say where the course is, and
                      // a dangling ", " looks like a bug rather than a blank.
                      [c.city, c.state].where((p) => p.isNotEmpty).join(', '),
                      '${c.tees.length} tee${c.tees.length == 1 ? '' : 's'}',
                    ].where((p) => p.isNotEmpty).join(' • '),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: ValueKey('edit-course-${c.id}'),
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Edit course',
                        onPressed: () => _openEditCourse(c),
                      ),
                      IconButton(
                        key: ValueKey('delete-course-${c.id}'),
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Remove course',
                        onPressed: () => _confirmDelete(c),
                      ),
                    ],
                  ),
                  // Tapping the row selects it for the scorecard below; the
                  // pencil opens the editor.
                  onTap: () => setState(() {
                    selectedCourseId = c.id;
                    selectedTeeId = null;
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
                'No course selected. Search local ratings or add a course manually.',
              ),
            ),
          if (course != null && tee != null) ...[
            SizedBox(
              width: double.infinity,
              child: DropdownButtonFormField<String>(
                key: ValueKey('tee-dropdown-${course.id}'),
                initialValue: tee.id,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Teebox'),
                // The closed field shows plain text; the open menu boxes
                // each option so adjacent tees don't run together.
                selectedItemBuilder: (context) => [
                  for (final t in course.tees)
                    Text(teeLabel(t), overflow: TextOverflow.ellipsis),
                ],
                items: [
                  for (final t in course.tees)
                    DropdownMenuItem(
                      value: t.id,
                      child: Container(
                        key: ValueKey('tee-option-${t.id}'),
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: Insets.sm,
                          vertical: Insets.xs,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                          borderRadius: BorderRadius.circular(Insets.sm),
                        ),
                        child: Text(
                          teeLabel(t),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => selectedTeeId = v),
              ),
            ),
            Container(
              key: const ValueKey('scorecard-outline'),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(Radii.control),
              ),
              clipBehavior: Clip.antiAlias,
              child: scorecardTable(course, tee),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => photoUsable(course.imagePath)
                    ? showCoursePhoto(
                        context,
                        course.name,
                        course.imagePath,
                        onDelete: () => _deleteCoursePhoto(course),
                      )
                    : _addCoursePhoto(course),
                icon: Icon(
                  photoUsable(course.imagePath)
                      ? Icons.photo_outlined
                      : Icons.add_a_photo_outlined,
                ),
                label: Text(
                  photoUsable(course.imagePath)
                      ? 'View Scorecard Photo'
                      : 'Save Blank Scorecard',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Compact course picker shown once the saved list outgrows cards.
  ///
  /// The dropdown holds the same search-filtered courses the cards would;
  /// edit and delete act on the selected course so no action is lost.
  Widget _savedCourseDropdown(
    BuildContext context,
    List<Course> courses,
    Course? selected,
  ) {
    // The selection survives typing, so it can lag the filtered list; a
    // value outside the items would throw, hence the membership check.
    final value = courses.any((c) => c.id == selectedCourseId)
        ? selectedCourseId
        : null;
    return Card(
      margin: const EdgeInsets.only(top: Insets.xs),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Insets.sm),
        child: Row(
          children: [
            Icon(
              Icons.golf_course_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: Insets.xs),
            Expanded(
              child: DropdownButton<String>(
                key: const ValueKey('course-dropdown'),
                value: value,
                hint: const Text('Select a course'),
                isExpanded: true,
                underline: const SizedBox.shrink(),
                items: [
                  for (final c in courses)
                    DropdownMenuItem(
                      value: c.id,
                      child: Text(c.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() {
                  selectedCourseId = v;
                  selectedTeeId = null;
                }),
              ),
            ),
            if (selected != null) ...[
              IconButton(
                key: ValueKey('edit-course-${selected.id}'),
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Edit course',
                onPressed: () => _openEditCourse(selected),
              ),
              IconButton(
                key: ValueKey('delete-course-${selected.id}'),
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Remove course',
                onPressed: () => _confirmDelete(selected),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openCatalogCourse(CourseCatalogCourse course) async {
    final catalog = _courseCatalog;
    if (catalog == null ||
        _loadingCatalogCourses.contains(course.appCourseId)) {
      return;
    }
    setState(() => _loadingCatalogCourses.add(course.appCourseId));
    late final List<CourseCatalogTee> catalogTees;
    try {
      catalogTees = await catalog.teesFor(course);
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingCatalogCourses.remove(course.appCourseId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load local tee data: $error')),
      );
      return;
    }
    if (!mounted) return;
    if (catalogTees.isEmpty) {
      setState(() => _loadingCatalogCourses.remove(course.appCourseId));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No usable tees were found locally.')),
      );
      return;
    }

    List<OpenGolfTee> onlineTees = const [];
    List<OpenGolfHoleFull> onlineHoles = const [];
    var onlineStatus =
        'Online scorecard data is unavailable. Tee ratings are '
        'filled from the local catalog; enter pars and yardages from the '
        'course scorecard before saving.';
    var onlineAttribution = false;
    try {
      final candidates = await _openGolfApi.search(
        '${course.name} ${course.city} ${course.state}',
      );
      final match = matchOnlineCatalogCourse(course, candidates);
      if (match == null) {
        onlineStatus =
            'No unambiguous online scorecard match was found. Local tee '
            'ratings are prefilled; verify pars and enter yardages manually.';
      } else {
        final data = await _openGolfApi.fetchScorecard(match.id);
        onlineTees = data.tees;
        onlineHoles = data.holes;
        onlineAttribution = true;
      }
    } on OpenGolfException catch (error) {
      onlineStatus = error.message;
    } catch (error) {
      onlineStatus = 'Online scorecard data could not be read: $error';
    }
    final imported = buildCourseCatalogTeeImport(
      courseId: course.appCourseId,
      catalogTees: catalogTees,
      onlineTees: onlineTees,
      onlineHoles: onlineHoles,
    );
    if (onlineAttribution) onlineStatus = imported.onlineStatus;
    if (!mounted) return;
    setState(() => _loadingCatalogCourses.remove(course.appCourseId));
    _searchFocus.unfocus();
    final existing = widget.store.courseById(course.appCourseId);
    if (existing != null) {
      await _openEditCourse(
        existing,
        importedCatalogTees: imported.tees,
        catalogParTotals: imported.expectedParByTee,
        missingParHolesByTee: imported.missingParHolesByTee,
        catalogOnlineStatus: onlineStatus,
        onlineAttribution: onlineAttribution,
      );
      return;
    }
    await _openAddCourse(
      catalogCourse: course,
      importedCatalogTees: imported.tees,
      catalogParTotals: imported.expectedParByTee,
      missingParHolesByTee: imported.missingParHolesByTee,
      catalogOnlineStatus: onlineStatus,
      onlineAttribution: onlineAttribution,
    );
  }

  Future<void> _openEditCourse(
    Course c, {
    CourseCatalogTee? catalogTee,
    List<Tee> importedCatalogTees = const [],
    Map<String, int> catalogParTotals = const {},
    Map<String, List<int>> missingParHolesByTee = const {},
    String? catalogOnlineStatus,
    bool onlineAttribution = false,
  }) async {
    final updated = await Navigator.of(context).push<Course>(
      MaterialPageRoute(
        builder: (_) => AddCourseScreen(
          existing: c,
          catalogTee: catalogTee,
          importedCatalogTees: importedCatalogTees,
          catalogParTotals: catalogParTotals,
          missingParHolesByTee: missingParHolesByTee,
          catalogOnlineStatus: catalogOnlineStatus,
          onlineAttribution: onlineAttribution,
        ),
      ),
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
    CourseCatalogCourse? catalogCourse,
    CourseCatalogTee? catalogTee,
    List<Tee> importedCatalogTees = const [],
    Map<String, int> catalogParTotals = const {},
    Map<String, List<int>> missingParHolesByTee = const {},
    String? catalogOnlineStatus,
    bool onlineAttribution = false,
  }) async {
    final created = await Navigator.of(context).push<Course>(
      MaterialPageRoute(
        builder: (_) => AddCourseScreen(
          catalogCourse: catalogCourse,
          catalogTee: catalogTee,
          importedCatalogTees: importedCatalogTees,
          catalogParTotals: catalogParTotals,
          missingParHolesByTee: missingParHolesByTee,
          catalogOnlineStatus: catalogOnlineStatus,
          onlineAttribution: onlineAttribution,
        ),
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

  Future<void> _addCoursePhoto(Course course) async {
    final result = await pickScorecardPhoto(context);
    if (result is! PhotoPicked) return;
    final path = await persistScanPhoto(result.file, course.id);
    if (!mounted) return;
    widget.store.updateCourse(course.copyWithImagePath(path));
    setState(() {});
  }

  Future<void> _deleteCoursePhoto(Course course) async {
    final old = course.imagePath;
    widget.store.updateCourse(course.copyWithImagePath(''));
    await deleteScanPhoto(old);
    if (mounted) setState(() {});
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
  /// When set, the form edits this saved custom course instead of adding.
  final Course? existing;
  final CourseCatalogCourse? catalogCourse;
  final CourseCatalogTee? catalogTee;
  final List<Tee> importedCatalogTees;
  final Map<String, int> catalogParTotals;
  final Map<String, List<int>> missingParHolesByTee;
  final String? catalogOnlineStatus;
  final bool onlineAttribution;
  const AddCourseScreen({
    super.key,
    this.existing,
    this.catalogCourse,
    this.catalogTee,
    this.importedCatalogTees = const [],
    this.catalogParTotals = const {},
    this.missingParHolesByTee = const {},
    this.catalogOnlineStatus,
    this.onlineAttribution = false,
  }) : assert(catalogCourse != null || catalogTee == null || existing != null);
  @override
  State<AddCourseScreen> createState() => _AddCourseScreenState();
}

/// One tee box being drafted. Pars, yardages and hole indexes belong to each tee.
class _TeeDraft {
  final TextEditingController nameCtrl;
  final TextEditingController ratingCtrl = TextEditingController();
  final TextEditingController slopeCtrl = TextEditingController();
  final TextEditingController frontNineRatingCtrl = TextEditingController();
  final TextEditingController frontNineSlopeCtrl = TextEditingController();
  final TextEditingController backNineRatingCtrl = TextEditingController();
  final TextEditingController backNineSlopeCtrl = TextEditingController();
  List<int> pars;
  Set<int> parNeedsReview = {};
  int? catalogPar;
  List<int> yards;
  List<int?> strokeIndexes;
  _TeeDraft(String name, int holes)
    : nameCtrl = TextEditingController(text: name),
      pars = List.filled(holes, 4),
      yards = List.filled(holes, 0),
      strokeIndexes = List<int?>.filled(holes, null);

  /// A tee the database already knows: rating, slope and yardage come across
  /// filled in, so nothing has to be retyped and nothing is guessed.
  factory _TeeDraft.fromTee(Tee t) {
    final d = _TeeDraft(t.name, t.holes.length)
      ..ratingCtrl.text = t.rating.toStringAsFixed(1)
      ..slopeCtrl.text = '${t.slope}'
      ..frontNineRatingCtrl.text = t.frontNineRating?.toStringAsFixed(1) ?? ''
      ..frontNineSlopeCtrl.text = t.frontNineSlope?.toString() ?? ''
      ..backNineRatingCtrl.text = t.backNineRating?.toStringAsFixed(1) ?? ''
      ..backNineSlopeCtrl.text = t.backNineSlope?.toString() ?? ''
      ..pars = [for (final h in t.holes) h.par]
      ..yards = [for (final h in t.holes) h.yardage]
      ..strokeIndexes = [for (final h in t.holes) h.strokeIndex];
    return d;
  }

  void resize(int holes) {
    if (yards.length == holes) return;
    yards = List.generate(holes, (i) => i < yards.length ? yards[i] : 0);
    pars = List.generate(holes, (i) => i < pars.length ? pars[i] : 4);
    strokeIndexes = List.generate(
      holes,
      (i) => i < strokeIndexes.length ? strokeIndexes[i] : null,
    );
  }

  void dispose() {
    nameCtrl.dispose();
    ratingCtrl.dispose();
    slopeCtrl.dispose();
    frontNineRatingCtrl.dispose();
    frontNineSlopeCtrl.dispose();
    backNineRatingCtrl.dispose();
    backNineSlopeCtrl.dispose();
  }
}

class _AddCourseScreenState extends State<AddCourseScreen> {
  final nameCtrl = TextEditingController();
  final cityCtrl = TextEditingController();
  final stateCtrl = TextEditingController();
  final _photoZoom = _ScorecardZoom();
  int holesCount = 18;
  final List<_TeeDraft> tees = [];
  List<int> get pars => tees[editYardsTee.clamp(0, tees.length - 1)].pars;
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
      for (final t in edit.tees) {
        final d = _TeeDraft.fromTee(t);
        final importedCourseTee = widget.importedCatalogTees
            .where((tee) => tee.name.toLowerCase() == t.name.toLowerCase())
            .firstOrNull;
        final importedTee =
            widget.catalogTee != null &&
                t.name.toLowerCase() ==
                    widget.catalogTee!.displayName.toLowerCase()
            ? widget.catalogTee
            : null;
        if (importedTee != null) {
          if (importedTee.frontNineRating != null &&
              d.frontNineRatingCtrl.text.trim().isEmpty) {
            d.frontNineRatingCtrl.text = importedTee.frontNineRating!
                .toStringAsFixed(1);
          }
          if (importedTee.frontNineSlope != null &&
              d.frontNineSlopeCtrl.text.trim().isEmpty) {
            d.frontNineSlopeCtrl.text = '${importedTee.frontNineSlope}';
          }
          if (importedTee.backNineRating != null &&
              d.backNineRatingCtrl.text.trim().isEmpty) {
            d.backNineRatingCtrl.text = importedTee.backNineRating!
                .toStringAsFixed(1);
          }
          if (importedTee.backNineSlope != null &&
              d.backNineSlopeCtrl.text.trim().isEmpty) {
            d.backNineSlopeCtrl.text = '${importedTee.backNineSlope}';
          }
        }
        for (var i = 0; i < d.yards.length && i < t.holes.length; i++) {
          if (d.yards[i] == 0) {
            d.yards[i] = t.holes[i].yardage;
          }
          if (importedCourseTee != null &&
              d.yards[i] == 0 &&
              i < importedCourseTee.holes.length) {
            d.yards[i] = importedCourseTee.holes[i].yardage;
          }
        }
        tees.add(d);
      }
      for (final importedTee in widget.importedCatalogTees) {
        if (edit.tees.any(
          (t) => t.name.toLowerCase() == importedTee.name.toLowerCase(),
        )) {
          continue;
        }
        final draft = _TeeDraft.fromTee(importedTee)
          ..catalogPar = widget.catalogParTotals[importedTee.name]
          ..parNeedsReview = {
            ...?widget.missingParHolesByTee[importedTee.name],
          };
        tees.add(draft);
      }
      final catalogTee = widget.catalogTee;
      if (catalogTee != null &&
          !edit.tees.any(
            (t) => t.name.toLowerCase() == catalogTee.displayName.toLowerCase(),
          )) {
        final d = _TeeDraft(catalogTee.displayName, holesCount)
          ..ratingCtrl.text = catalogTee.rating.toStringAsFixed(1)
          ..slopeCtrl.text = '${catalogTee.slope}'
          ..frontNineRatingCtrl.text =
              catalogTee.frontNineRating?.toStringAsFixed(1) ?? ''
          ..frontNineSlopeCtrl.text =
              catalogTee.frontNineSlope?.toString() ?? ''
          ..backNineRatingCtrl.text =
              catalogTee.backNineRating?.toStringAsFixed(1) ?? ''
          ..backNineSlopeCtrl.text = catalogTee.backNineSlope?.toString() ?? '';
        tees.add(d);
      }
      keptPhoto = edit.imagePath;
      return;
    }
    final catalogCourse = widget.catalogCourse;
    final catalogTee = widget.catalogTee;
    if (catalogCourse != null && widget.importedCatalogTees.isNotEmpty) {
      nameCtrl.text = catalogCourse.name;
      cityCtrl.text = catalogCourse.city;
      stateCtrl.text = catalogCourse.state;
      holesCount = widget.importedCatalogTees.first.holes.length;
      for (final tee in widget.importedCatalogTees) {
        final draft = _TeeDraft.fromTee(tee)
          ..catalogPar = widget.catalogParTotals[tee.name]
          ..parNeedsReview = {...?widget.missingParHolesByTee[tee.name]};
        tees.add(draft);
      }
      return;
    }
    if (catalogCourse != null && catalogTee != null) {
      nameCtrl.text = catalogCourse.name;
      cityCtrl.text = catalogCourse.city;
      stateCtrl.text = catalogCourse.state;
      holesCount = catalogTee.holes;
      final draft = _TeeDraft(catalogTee.displayName, holesCount)
        ..ratingCtrl.text = catalogTee.rating.toStringAsFixed(1)
        ..slopeCtrl.text = '${catalogTee.slope}'
        ..frontNineRatingCtrl.text =
            catalogTee.frontNineRating?.toStringAsFixed(1) ?? ''
        ..frontNineSlopeCtrl.text = catalogTee.frontNineSlope?.toString() ?? ''
        ..backNineRatingCtrl.text =
            catalogTee.backNineRating?.toStringAsFixed(1) ?? ''
        ..backNineSlopeCtrl.text = catalogTee.backNineSlope?.toString() ?? '';
      tees.add(draft);
      return;
    }
    tees.add(_TeeDraft('White', holesCount));
  }

  void _setHoles(int n) {
    setState(() {
      holesCount = n;
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
      body: Theme(
        data: Theme.of(context).copyWith(
          inputDecorationTheme: Theme.of(context).inputDecorationTheme.copyWith(
            isDense: false,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: Insets.md,
              vertical: Insets.lg,
            ),
          ),
        ),
        child: LayoutBuilder(
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
                        widget.catalogTee != null
                            ? 'Published tee ratings and total par are prefilled from the local catalog. Review or edit pars and yardages when you have the scorecard; you can save now and edit later.'
                            : widget.importedCatalogTees.isNotEmpty
                            ? 'All tee ratings from the local catalog are prefilled. Online pars and available yardages are included; unknown pars default to 4 and missing yardages stay blank. You can save now and edit later.'
                            : 'Copy par, rating and slope from the scorecard. Saved on-device, works offline.',
                      ),
                      if (widget.catalogOnlineStatus != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          '${widget.catalogOnlineStatus}${widget.onlineAttribution ? '\n$openGolfAttribution' : ''}',
                          style: AppType.meta.copyWith(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      if (scanning) ...[
                        const LinearProgressIndicator(),
                        const SizedBox(height: 4),
                        Text(
                          scanStatus,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
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
                      const SizedBox(height: Insets.sm),
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
                      const SizedBox(height: Insets.sm),
                      TextField(
                        controller: cityCtrl,
                        decoration: const InputDecoration(labelText: 'City'),
                      ),
                      const SizedBox(height: Insets.sm),
                      TextField(
                        controller: stateCtrl,
                        decoration: const InputDecoration(labelText: 'State'),
                      ),
                      const SizedBox(height: Insets.md),
                      Row(
                        children: [
                          const Text('Holes: '),
                          for (final n in [9, 18])
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: ChoiceChip(
                                label: Text('$n'),
                                selected: holesCount == n,
                                showCheckmark: false,
                                onSelected:
                                    widget.catalogTee == null &&
                                        widget.importedCatalogTees.isEmpty
                                    ? (_) => _setHoles(n)
                                    : null,
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
                        holesCount == 9
                            ? 'For a 9-hole course, enter its published 9-hole rating and slope. For an 18-hole course, enter its overall rating and slope.'
                            : 'Add one per color you play. Enter the published rating and slope for each tee.',
                        style: AppType.meta.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      for (var ti = 0; ti < tees.length; ti++)
                        Card(
                          margin: const EdgeInsets.only(bottom: Insets.md),
                          child: Padding(
                            padding: const EdgeInsets.all(Insets.md),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: tees[ti].nameCtrl,
                                        decoration: InputDecoration(
                                          labelText: 'Teebox ${ti + 1}',
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
                                          holesCount = tees.first.pars.length;
                                        }),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: Insets.sm),
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
                                if (holesCount == 18) ...[
                                  const SizedBox(height: 8),
                                  const SizedBox(height: Insets.sm),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller:
                                              tees[ti].frontNineRatingCtrl,
                                          decoration: const InputDecoration(
                                            labelText: 'Front 9 rating',
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
                                          controller:
                                              tees[ti].frontNineSlopeCtrl,
                                          decoration: const InputDecoration(
                                            labelText: 'Front 9 slope',
                                          ),
                                          keyboardType: TextInputType.number,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: Insets.sm),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller:
                                              tees[ti].backNineRatingCtrl,
                                          decoration: const InputDecoration(
                                            labelText: 'Back 9 rating',
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
                                          controller:
                                              tees[ti].backNineSlopeCtrl,
                                          decoration: const InputDecoration(
                                            labelText: 'Back 9 slope',
                                          ),
                                          keyboardType: TextInputType.number,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: Insets.sm),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _addTee,
                          icon: const Icon(Icons.add),
                          label: const Text('Add another tee box'),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _openUsgaRatingDatabase,
                          icon: const Icon(Icons.open_in_new),
                          label: const Text(
                            'Look up published ratings in the USGA database',
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Holes (pars and yardages for the selected tee):',
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
                          color: Theme.of(
                            context,
                          ).colorScheme.tertiaryContainer,
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
                              showCheckmark: false,
                              onSelected: (_) => setState(() {
                                editYardsTee = ti;
                                holesCount = tees[ti].pars.length;
                              }),
                            ),
                        ],
                      ),
                      for (var i = 0; i < yardsTee.pars.length; i++)
                        _holeRow(i, yardsTee),
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
    final parNeedsReview =
        yardsTee.parNeedsReview.contains(i + 1) || parUncertain.contains(i + 1);
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
                    yardsTee.pars[i] = yardsTee.pars[i] >= 5
                        ? 3
                        : yardsTee.pars[i] + 1;
                    yardsTee.parNeedsReview.remove(i + 1);
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
                      decoration: parNeedsReview
                          ? BoxDecoration(
                              color: scheme.tertiaryContainer,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: scheme.tertiary),
                            )
                          : null,
                      child: Text(
                        '${parNeedsReview ? '? ' : ''}Par: ${yardsTee.pars[i]}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: parNeedsReview
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
              const SizedBox(width: 8),
              SizedBox(
                width: 62,
                child: TextFormField(
                  key: ValueKey(
                    'hcp-${identityHashCode(yardsTee)}-${yardsTee.strokeIndexes.length}-$i',
                  ),
                  initialValue: yardsTee.strokeIndexes[i]?.toString() ?? '',
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    labelText: 'HCP',
                    hintText: '-',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 8,
                    ),
                  ),
                  onChanged: (value) {
                    final text = value.trim();
                    yardsTee.strokeIndexes[i] = text.isEmpty
                        ? null
                        : int.tryParse(text) ?? -1;
                  },
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
    List<int>? scannedPars;
    setState(() {
      scanning = false;
      scanPhoto = file;
      _photoZoom.reset();
      lastOcrText = rawText;
      lastOcrAttempts = List.of(allTexts);
      parUncertain = const {};
      parFromYardages = false;
      if (scan.pars.length == 18 || scan.pars.length == 9) {
        holesCount = scan.pars.length;
        scannedPars = List.of(scan.pars);
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
          scannedPars = List.of(proposal.pars);
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
          if (scannedPars != null) d.pars = List.of(scannedPars!);
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
          if (scannedPars != null) t.pars = List.of(scannedPars!);
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
      // Preserve the scanned handicap row only when it is a complete valid
      // permutation; missing or unreadable values remain blank for editing.
      if (validStrokeIndexes(scan.hcp, holesCount)) {
        for (final tee in tees) {
          tee.strokeIndexes = List<int?>.of(scan.hcp);
        }
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

  Future<void> _openUsgaRatingDatabase() async {
    var message = 'Could not open the USGA Course Rating Database.';
    try {
      final opened = await launchUrl(
        Uri.https('ncrdb.usga.org'),
        mode: LaunchMode.externalApplication,
      );
      if (opened) return;
    } catch (error) {
      message = 'Could not open the USGA Course Rating Database: $error';
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
      final teeHoles = t.pars.length;
      final minRating = teeHoles == 9 ? 20.0 : 45.0;
      final maxRating = teeHoles == 9 ? 45.0 : 90.0;
      if (rating == null || rating < minRating || rating > maxRating) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              teeHoles == 9
                  ? 'Enter the 9-hole course rating for "$tName" from the scorecard (20–45).'
                  : 'Enter the course rating for "$tName" from the scorecard (45–90).',
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
      final enteredIndexes = <int>{};
      for (final index in t.strokeIndexes.whereType<int>()) {
        if (index < 1 || index > teeHoles) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Enter a valid HCP from 1 to $teeHoles for "$tName", or leave it blank.',
              ),
            ),
          );
          return;
        }
        if (!enteredIndexes.add(index)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'HCP $index is entered more than once for "$tName".',
              ),
            ),
          );
          return;
        }
      }
      if (teeHoles == 18) {
        for (final nine in [
          (
            label: 'Front 9',
            rating: t.frontNineRatingCtrl.text.trim(),
            slope: t.frontNineSlopeCtrl.text.trim(),
          ),
          (
            label: 'Back 9',
            rating: t.backNineRatingCtrl.text.trim(),
            slope: t.backNineSlopeCtrl.text.trim(),
          ),
        ]) {
          if (nine.rating.isEmpty && nine.slope.isEmpty) continue;
          final nineRating = double.tryParse(nine.rating);
          final nineSlope = int.tryParse(nine.slope);
          if (nineRating == null ||
              nineRating < 20 ||
              nineRating > 45 ||
              nineSlope == null ||
              nineSlope < 55 ||
              nineSlope > 155) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Enter both the ${nine.label} rating (20–45) and slope (55–155) for "$tName", or leave both blank.',
                ),
              ),
            );
            return;
          }
        }
      }
    }
    final id =
        widget.existing?.id ??
        widget.catalogCourse?.appCourseId ??
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
              frontNineRating: double.tryParse(
                tees[ti].frontNineRatingCtrl.text.trim(),
              ),
              frontNineSlope: int.tryParse(
                tees[ti].frontNineSlopeCtrl.text.trim(),
              ),
              backNineRating: double.tryParse(
                tees[ti].backNineRatingCtrl.text.trim(),
              ),
              backNineSlope: int.tryParse(
                tees[ti].backNineSlopeCtrl.text.trim(),
              ),
              holes: List.generate(tees[ti].pars.length, (i) {
                return HoleInfo(
                  number: i + 1,
                  par: tees[ti].pars[i],
                  yardage: tees[ti].yards[i],
                  strokeIndex: tees[ti].strokeIndexes[i],
                );
              }),
            ),
        ],
        custom: widget.existing?.custom ?? true,
        imagePath: imagePath,
        ocrText: lastOcrText,
        ocrAttempts: lastOcrAttempts,
      ),
    );
  }
}

// ---------------- STATS ----------------
class StatsPage extends StatefulWidget {
  final GolfStore store;
  const StatsPage({super.key, required this.store});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  // 'course' groups alphabetically, 'date' by latest round, 'score' by best.
  String _sort = 'course';

  int? _courseHandicap(Round round) {
    if (round.courseHandicap != null) return round.courseHandicap;
    final tee = widget.store.teeById(round.courseId, round.teeId);
    if (tee == null) return null;
    // Backfilled from the live index when no earlier index exists (rounds
    // posted before any index, or all on the same day): the avatar shows
    // what the round carries under the current index.
    final index =
        round.handicapIndexAtPlay ??
        widget.store.handicapIndexBefore(round.playedAt) ??
        widget.store.handicapIndex;
    if (index == null) return null;
    final ch = tee.courseHandicapForRound(
      holesPlayed: round.holes.length,
      startHole: round.startHole,
      handicapIndex: index,
    );
    if (ch != null) return ch;
    // Nine holes on a tee without published nine-hole ratings: a nine-hole
    // tee's own rating covers nine directly, otherwise halve the full tee.
    if (round.holes.length == 9) {
      final full = whs.courseHandicap(
        handicapIndex: index,
        slopeRating: tee.slope.toDouble(),
        courseRating: tee.rating,
        par: tee.par,
      );
      return tee.holes.length == 9 ? full : (full / 2).round();
    }
    return null;
  }

  /// The course's own handicap for the live index, on the most recently
  /// played tee: HI × (slope ÷ 113) + (rating − par), rounded. A dash when
  /// the index or the tee cannot be resolved.
  String _headerCourseHandicap(String courseId, List<Round> rounds) {
    final store = widget.store;
    final hi = store.handicapIndex;
    final course = store.courseById(courseId);
    if (hi == null || course == null || course.tees.isEmpty) return '—';
    final ordered = rounds.toList()
      ..sort((a, b) => b.playedAt.compareTo(a.playedAt));
    Tee? tee;
    for (final round in ordered) {
      tee = store.teeById(round.courseId, round.teeId);
      if (tee != null) break;
    }
    tee ??= course.defaultTee;
    return '${whs.courseHandicap(handicapIndex: hi, slopeRating: tee.slope.toDouble(), courseRating: tee.rating, par: tee.par)}';
  }

  String _roundDate(DateTime date) {
    final local = date.toLocal();
    return '${local.month.toString().padLeft(2, '0')}/'
        '${local.day.toString().padLeft(2, '0')}/'
        '${local.year}';
  }

  /// Total for the front (holes 1-9) or back (10-18) as scorecard numbering
  /// goes, against the nine the round actually covers. A nine the round never
  /// touches shows a dash.
  String _nineScore(Round round, {required bool front}) {
    var total = 0;
    var seen = false;
    for (var i = 0; i < round.holes.length; i++) {
      final at = round.startHole + i;
      if (front ? at < 9 : at >= 9) {
        total += round.holes[i].score;
        seen = true;
      }
    }
    return seen ? '$total' : '—';
  }

  DateTime _latestPlayed(List<Round> rounds) =>
      rounds.map((r) => r.playedAt).reduce((a, b) => a.isAfter(b) ? a : b);

  int _bestTotal(List<Round> rounds) =>
      rounds.map((r) => r.totalGross).reduce((a, b) => a < b ? a : b);

  /// Rows newest-first, except score sort which leads with the best round.
  List<Round> _sortedRows(List<Round> rounds) {
    final out = rounds.toList();
    if (_sort == 'score') {
      out.sort((a, b) {
        final byScore = a.totalGross.compareTo(b.totalGross);
        return byScore != 0 ? byScore : b.playedAt.compareTo(a.playedAt);
      });
    } else {
      out.sort((a, b) => b.playedAt.compareTo(a.playedAt));
    }
    return out;
  }

  /// One course's round rows. Date sort walks newest-first, so a year
  /// separator labels each block of rounds that falls into an older year.
  List<Widget> _roundRows(List<Round> rounds) {
    final children = <Widget>[];
    var lastYear = 0;
    for (final round in _sortedRows(rounds)) {
      final year = round.playedAt.year;
      if (_sort == 'date' && lastYear != 0 && year != lastYear) {
        children.add(_yearDivider(year));
      }
      lastYear = year;
      children.add(_roundCard(round));
    }
    return children;
  }

  Widget _yearDivider(int year) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Row(
      children: [
        Text(
          '$year',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Divider(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ],
    ),
  );

  Widget _roundCard(Round round) => Card(
    key: ValueKey('stats-round-${round.id}'),
    margin: const EdgeInsets.only(top: 6),
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: ListTile(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PostPage(store: widget.store, existing: round),
          ),
        );
        if (mounted) setState(() {});
      },
      leading: Semantics(
        label:
            'Course handicap ${_courseHandicap(round) ?? 'not available'}',
        child: CircleAvatar(
          backgroundColor: Theme.of(
            context,
          ).colorScheme.primaryContainer,
          foregroundColor: Theme.of(
            context,
          ).colorScheme.onPrimaryContainer,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'CH',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${_courseHandicap(round) ?? '—'}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
      title: Text(
        'Total: ${round.totalGross} • '
        '(F) ${_nineScore(round, front: true)} • '
        '(B) ${_nineScore(round, front: false)}',
      ),
      subtitle: Text(
        '${_roundDate(round.playedAt)} • '
        '${round.holes.length} holes • '
        'Putts ${round.totalPutts} • '
        'Pen ${round.totalPenalties}',
      ),
      trailing: photoUsable(round.imagePath)
          ? IconButton(
              key: ValueKey('stats-round-photo-${round.id}'),
              icon: const Icon(Icons.photo_outlined),
              tooltip: 'View scorecard photo',
              onPressed: () => showCoursePhoto(
                context,
                widget.store.courseById(round.courseId)?.name ?? 'Round',
                round.imagePath,
              ),
            )
          : null,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final s = store.statSummary();
    final roundsByCourse = <String, List<Round>>{};
    for (final round in store.rounds) {
      roundsByCourse.putIfAbsent(round.courseId, () => []).add(round);
    }
    String groupName(String id) =>
        store.courseById(id)?.name.toLowerCase() ?? id.toLowerCase();
    final courseIds = roundsByCourse.keys.toList()
      ..sort((left, right) {
        switch (_sort) {
          case 'date':
            final byDate = _latestPlayed(
              roundsByCourse[right]!,
            ).compareTo(_latestPlayed(roundsByCourse[left]!));
            return byDate != 0
                ? byDate
                : groupName(left).compareTo(groupName(right));
          case 'score':
            final byScore = _bestTotal(
              roundsByCourse[left]!,
            ).compareTo(_bestTotal(roundsByCourse[right]!));
            return byScore != 0
                ? byScore
                : groupName(left).compareTo(groupName(right));
          default:
            return groupName(left).compareTo(groupName(right));
        }
      });
    return Scaffold(
      appBar: AppBar(title: const Text('Performance')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
          Text(
            'Courses Played',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: const ValueKey('stats-sort'),
            initialValue: _sort,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Sort by'),
            items: const [
              DropdownMenuItem(value: 'course', child: Text('Course')),
              DropdownMenuItem(value: 'date', child: Text('Date')),
              DropdownMenuItem(value: 'score', child: Text('Score')),
            ],
            onChanged: (v) => setState(() => _sort = v ?? 'course'),
          ),
          const SizedBox(height: 8),
          for (final courseId in courseIds)
            Card(
              key: ValueKey('stats-course-$courseId'),
              margin: const EdgeInsets.only(bottom: 8),
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                key: PageStorageKey('stats-course-expansion-$courseId'),
                tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                title: Text(
                  store.courseById(courseId)?.name ?? 'Unknown course',
                  style: AppType.title,
                ),
                subtitle: Text(
                  [
                    _plural(roundsByCourse[courseId]!.length, 'round'),
                    'CH ${_headerCourseHandicap(courseId, roundsByCourse[courseId]!)}',
                  ].join(' • '),
                ),
                trailing: const Icon(Icons.keyboard_arrow_down),
                children: _roundRows(roundsByCourse[courseId]!),
              ),
            ),
          const SizedBox(height: 20),
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Version ${appVersion.split('+').first}',
                key: const ValueKey('stats-app-version'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
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

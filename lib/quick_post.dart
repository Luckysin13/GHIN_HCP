import 'package:flutter/material.dart';

import 'models.dart';
import 'score_entry.dart';
import 'store.dart';
import 'whs.dart' as whs_engine;

/// Quick score entry on the Home screen.
///
/// Mirrors the Play page's course/tee section, then takes the round as a
/// single typed total ("75") rather than 18 numbers or a stepper per hole.
/// [spreadTotal] lays that total out across the holes played. The Play page
/// stays the place for per-hole stats like putts and GIR; this is for getting
/// a round recorded in a few seconds.
class QuickPostCard extends StatefulWidget {
  final GolfStore store;

  /// Called after a round is added, so Home can show its own confirmation.
  final ValueChanged<Round>? onPosted;

  const QuickPostCard({super.key, required this.store, this.onPosted});

  @override
  State<QuickPostCard> createState() => _QuickPostCardState();
}

class _QuickPostCardState extends State<QuickPostCard> {
  final _scoreCtrl = TextEditingController();
  final _scoreFocus = FocusNode();

  String? _courseId;
  String? _teeId;
  int _holesCount = 18;
  int _startHole = 0; // 0 = front nine, 9 = back nine
  bool _incompleteRoundReasonValid = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scoreCtrl.addListener(_onTyped);
    // Default to the course played most recently: posting a second round
    // usually means the same course again, and picking it first is the
    // common case. Falls back to the first course for a new golfer.
    final rounds = List<Round>.from(widget.store.rounds)
      ..sort((a, b) => b.playedAt.compareTo(a.playedAt));
    for (final r in rounds) {
      if (widget.store.teeById(r.courseId, r.teeId) != null) {
        _courseId = r.courseId;
        _teeId = r.teeId;
        return;
      }
    }
    if (widget.store.courses.isNotEmpty) {
      _courseId = widget.store.courses.first.id;
      _teeId = widget.store.courses.first.defaultTee.id;
    }
  }

  @override
  void dispose() {
    _scoreCtrl
      ..removeListener(_onTyped)
      ..dispose();
    _scoreFocus.dispose();
    super.dispose();
  }

  void _onTyped() {
    // Rebuild so the live total and the button's enabled state follow typing.
    if (mounted) setState(() {});
  }

  Tee? get _tee => (_courseId == null || _teeId == null)
      ? null
      : widget.store.teeById(_courseId!, _teeId!);

  Course? get _course =>
      _courseId == null ? null : widget.store.courseById(_courseId!);

  int get _expected => _holesCount;

  ScoreEntryResult get _entry => parseRoundTotal(_scoreCtrl.text, _pars);

  /// Pars for the holes this selection covers, padded to [_expected] so a tee
  /// edited down to 9 holes still shows a full-length par row.
  List<int> get _pars =>
      _tee?.parsFrom(_startHole, _expected) ?? List<int>.filled(_expected, 4);

  void _clearScores() {
    _scoreCtrl.clear();
    _incompleteRoundReasonValid = false;
    setState(() => _error = null);
  }

  void _post() {
    final tee = _tee;
    final course = _course;
    if (tee == null || course == null) {
      setState(() => _error = 'Pick a course and tee first');
      return;
    }

    // A tee with fewer holes than the selection can't hold the round, so the
    // pars would be invented. Say so instead of saving a score against par 4s.
    if (_startHole + _expected > tee.holes.length) {
      setState(
        () => _error =
            '${course.name} ${tee.name} only has ${tee.holes.length} holes',
      );
      return;
    }

    // Parsed only once the tee is known to be long enough, since the spread
    // needs the real pars of the holes played.
    final entry = _entry;
    if (!entry.isValid) {
      setState(() => _error = entry.message);
      return;
    }

    final playedAt = DateTime.now();
    final hi = widget.store.handicapIndexBefore(playedAt);
    final has18HoleRatings =
        tee.holes.length == 18 && _startHole == 0 && _expected >= 10;
    final ch = !has18HoleRatings || hi == null
        ? null
        : whs_engine.courseHandicap(
            handicapIndex: hi,
            slopeRating: tee.slope.toDouble(),
            courseRating: tee.rating,
            par: tee.par,
          );
    final round = Round(
      id: playedAt.microsecondsSinceEpoch.toString(),
      courseId: course.id,
      teeId: tee.id,
      playedAt: playedAt,
      format: 'stroke',
      isTournament: false,
      // putts 0, not the HoleScore default of 2: nothing was measured here,
      // and a fabricated 2 would quietly land in the Putts/Hole average.
      holes: [for (final s in entry.scores) HoleScore(score: s, putts: 0)],
      incompleteRoundReasonValid: _incompleteRoundReasonValid,
      courseHandicap: ch,
      handicapIndexAtPlay: hi,
      startHole: _startHole,
    );
    widget.store.addRound(round);
    _scoreFocus.unfocus();
    _clearScores();
    widget.onPosted?.call(round);
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final courses = store.courses;
    if (courses.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'No courses yet. Add one from the Courses tab to post a score.',
          ),
        ),
      );
    }

    // Repair a selection whose course or tee no longer exists (deleted, or the
    // store was reloaded under this widget).
    var course = _course;
    if (course == null || !courses.any((c) => c.id == course!.id)) {
      course = courses.first;
      _courseId = course.id;
      _teeId = course.defaultTee.id;
    }
    if (!course.tees.any((t) => t.id == _teeId)) {
      _teeId = course.defaultTee.id;
    }

    final tee = _tee!;
    final entry = _entry;
    final showEntryError = _scoreCtrl.text.trim().isNotEmpty && !entry.isValid;
    // Null when the tee is too short to cover the selection: showing a padded
    // par total there would be an invented number the user is asked to beat.
    final teeCovers = _startHole + _expected <= tee.holes.length ? tee : null;
    final parSum = teeCovers?.parTotalFrom(_startHole, _expected);
    final canPost = entry.isValid && teeCovers != null;
    final toPar = (entry.isValid && parSum != null)
        ? entry.total - parSum
        : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Quick score', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _courseId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Course'),
              items: [
                for (final c in courses)
                  DropdownMenuItem(value: c.id, child: Text(c.name)),
              ],
              onChanged: (v) => setState(() {
                _courseId = v;
                final nc = courses.firstWhere((c) => c.id == v);
                _teeId = nc.defaultTee.id;
                _holesCount = nc.defaultTee.holes.length == 18 ? 18 : 9;
                _startHole = 0;
                _clearScores();
              }),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _teeId,
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
                final selectedTee = course!.tees.firstWhere((t) => t.id == v);
                setState(() {
                  _teeId = v;
                  if (!holeCountOptionsForTee(
                    selectedTee.holes.length,
                  ).contains(_holesCount)) {
                    _holesCount = selectedTee.holes.length == 18 ? 18 : 9;
                  }
                  _startHole = 0;
                  _clearScores();
                });
              },
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              key: const ValueKey('home-hole-count-selector'),
              initialValue: _holesCount,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Holes'),
              items: [
                for (final n in holeCountOptionsForTee(tee.holes.length))
                  DropdownMenuItem(value: n, child: Text('$n Holes')),
              ],
              onChanged: (n) {
                if (n == null) return;
                setState(() {
                  _holesCount = n;
                  _startHole = 0;
                  _clearScores();
                });
              },
            ),
            if (_holesCount >= 10 && _holesCount < 18)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _incompleteRoundReasonValid,
                title: const Text(
                  'I had a valid reason for not completing the round',
                ),
                onChanged: (value) => setState(
                  () => _incompleteRoundReasonValid = value ?? false,
                ),
              ),
            // Only meaningful for a nine: which one decides the pars, and
            // therefore the course handicap frozen onto the round.
            if (_holesCount == 9) ...[
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('Front 9')),
                  ButtonSegment(value: 9, label: Text('Back 9')),
                ],
                selected: {_startHole},
                onSelectionChanged: (s) => setState(() {
                  _startHole = s.first;
                  _clearScores();
                }),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _scoreCtrl,
              focusNode: _scoreFocus,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => canPost ? _post() : null,
              decoration: InputDecoration(
                labelText: 'Total score',
                // Par sits in the placeholder, so the number the golfer has to
                // beat is visible without typing anything.
                hintText: '$parSum',
                helperText:
                    '${selectionLabel(_holesCount, _startHole)} • par $parSum',
                helperMaxLines: 2,
                border: const OutlineInputBorder(),
                suffixText: entry.isValid ? entry.total.toString() : null,
                suffixStyle: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: toPar == null
                      ? Theme.of(context).colorScheme.onSurface
                      : _diffColor(toPar),
                ),
                errorText: _error ?? (showEntryError ? entry.message : null),
              ),
            ),
            // Gated on parSum as well as the entry: on a tee too short for the
            // selection the entry can be valid while the par total is unknown.
            if (entry.isValid && toPar != null) ...[
              const SizedBox(height: 8),
              Text(
                'Total ${entry.total}  •  Par $parSum  •  '
                '${toPar >= 0 ? '+$toPar' : '$toPar'}',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: _diffColor(toPar),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.check),
                    label: const Text('Post Round'),
                    onPressed: canPost ? _post : null,
                  ),
                ),
                if (_scoreCtrl.text.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _clearScores,
                    child: const Text('Clear'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _diffColor(int d) =>
      Color(widget.store.scoreColorValue(d.clamp(-2, 3)));
}

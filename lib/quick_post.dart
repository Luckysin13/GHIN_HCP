import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'models.dart';
import 'photo_source_sheet.dart';
import 'scan_service.dart';
import 'score_entry.dart';
import 'store.dart';

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
  String? _error;
  XFile? _photo;
  double _pcc = 0.0;

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
      final firstCourse = widget.store.alphabeticalCourses.first;
      _courseId = firstCourse.id;
      _teeId = firstCourse.defaultTee.id;
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

  Round? get _lastCourseRound {
    final courseId = _courseId;
    if (courseId == null) return null;
    Round? latest;
    for (final round in widget.store.rounds) {
      if (round.courseId != courseId) continue;
      if (latest == null || round.playedAt.isAfter(latest.playedAt)) {
        latest = round;
      }
    }
    return latest;
  }

  int get _expected => _holesCount;

  List<int> _homeHoleCountOptions(Tee tee) => [
    if (tee.holes.length >= 9) 9,
    if (tee.holes.length >= 18) 18,
  ];

  String _teeOptionLabel(Tee tee) {
    final par = tee.parTotalFrom(_startHole, _holesCount);
    if (_holesCount == 9) {
      if (tee.holes.length == 9) {
        return '${tee.name} • 9-hole ${tee.rating.toStringAsFixed(1)}/${tee.slope} • Par $par';
      }
      final nineLabel = _startHole == 0 ? 'Front 9' : 'Back 9';
      final ratings = tee.nineHoleRatings(_startHole);
      if (ratings == null) {
        return '${tee.name} • $nineLabel rating unavailable • Par $par';
      }
      return '${tee.name} • $nineLabel ${ratings.rating.toStringAsFixed(1)}/${ratings.slope} • Par $par';
    }
    return '${tee.name} • ${tee.rating.toStringAsFixed(1)}/${tee.slope} • Par $par';
  }

  ScoreEntryResult get _entry => parseRoundTotal(_scoreCtrl.text, _pars);

  /// Pars for the holes this selection covers, padded to [_expected] so a tee
  /// edited down to 9 holes still shows a full-length par row.
  List<int> get _pars =>
      _tee?.parsFrom(_startHole, _expected) ?? List<int>.filled(_expected, 4);

  void _clearScores() {
    _scoreCtrl.clear();
    setState(() {
      _error = null;
      _photo = null;
    });
  }

  Future<void> _pickPhoto() async {
    final result = await pickScorecardPhoto(
      context,
      showRemove: _photo != null,
    );
    switch (result) {
      case null:
        return;
      case PhotoRemoved():
        setState(() => _photo = null);
      case PhotoPicked(:final file):
        setState(() => _photo = file);
    }
  }

  Future<void> _post() async {
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
    final ch = hi == null
        ? null
        : tee.courseHandicapForRound(
            holesPlayed: _expected,
            startHole: _startHole,
            handicapIndex: hi,
          );
    final roundId = playedAt.microsecondsSinceEpoch.toString();
    // Posting caps (net double bogey, or par + 5 while establishing) apply
    // to the stored card. The tee covers the selection here (checked above),
    // so every spread score has a real hole to draw par and index from.
    final adjustment = adjustScoresForPosting(
      handicapIndex: hi,
      courseHandicap: ch ?? 0,
      holes: [
        for (var i = 0; i < entry.scores.length; i++)
          (
            par: tee.holes[_startHole + i].par,
            // A hole with no published index ranks below every ranked hole.
            strokeIndex: tee.holes[_startHole + i].strokeIndex ?? 19,
            grossScore: entry.scores[i],
          ),
      ],
    );
    // Captured before the photo await so the capped note below never
    // touches a dead context.
    final messenger = ScaffoldMessenger.of(context);
    var imagePath = '';
    final photo = _photo;
    if (photo != null) {
      try {
        imagePath = await persistRoundPhoto(photo, roundId);
      } catch (_) {
        // The round matters more than its picture.
      }
    }
    final round = Round(
      id: roundId,
      courseId: course.id,
      teeId: tee.id,
      playedAt: playedAt,
      format: 'stroke',
      isTournament: false,
      // putts 0, not the HoleScore default of 2: nothing was measured here,
      // and a fabricated 2 would quietly land in the Putts/Hole average.
      holes: [
        for (final s in adjustment.holes)
          HoleScore(score: s.adjustedScore, putts: 0),
      ],
      courseHandicap: ch,
      handicapIndexAtPlay: hi,
      startHole: _startHole,
      pcc: _pcc,
      imagePath: imagePath,
    );
    widget.store.addRound(round);
    final capped = adjustment.cappedCount;
    if (capped > 0 && messenger.mounted) {
      final holesWord = capped == 1 ? 'hole' : 'holes';
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Posted ${adjustment.adjustedTotal} — $capped $holesWord capped at max.',
          ),
        ),
      );
    }
    _scoreFocus.unfocus();
    _clearScores();
    widget.onPosted?.call(round);
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final courses = store.alphabeticalCourses;
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
            const SizedBox(height: 4),
            Text(
              switch (_lastCourseRound) {
                final last? =>
                  'Last score at this course: ${last.totalGross} • ${last.holes.length} holes • ${widget.store.teeById(last.courseId, last.teeId)?.name ?? 'Tee unavailable'}',
                _ => 'No previous score at this course',
              },
              key: const ValueKey('quick-score-last-course-score'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _teeId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Teebox'),
              items: [
                for (final t in course.tees)
                  DropdownMenuItem(
                    value: t.id,
                    child: Text(
                      _teeOptionLabel(t),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) {
                if (v == null) return;
                final selectedTee = course!.tees.firstWhere((t) => t.id == v);
                setState(() {
                  _teeId = v;
                  if (!_homeHoleCountOptions(
                    selectedTee,
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
                for (final n in _homeHoleCountOptions(tee))
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
            const SizedBox(height: 8),
            DropdownButtonFormField<double>(
              key: const ValueKey('quick-score-pcc-selector'),
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
            // Field and picture button always share the row fifty-fifty. The
            // label shrinks to fit its half so narrow phones never overflow.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _scoreCtrl,
                    focusNode: _scoreFocus,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => canPost ? _post() : null,
                    decoration: InputDecoration(
                      labelText: 'Total score',
                      // Par sits in the placeholder, so the number the golfer
                      // has to beat is visible without typing anything.
                      hintText: '$parSum',
                      border: const OutlineInputBorder(),
                      errorText:
                          _error ?? (showEntryError ? entry.message : null),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('quick-score-photo'),
                    onPressed: _pickPhoto,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _photo == null
                              ? Icons.add_a_photo_outlined
                              : Icons.check_circle_outline,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _photo == null ? 'Save Scorecard' : 'Attached',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.check),
                label: const Text('Post Round'),
                onPressed: canPost ? _post : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

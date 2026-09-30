// Heuristic parser: raw OCR text from a scorecard photo -> structured data.
//
// Scorecards vary wildly and OCR is noisy, so this only extracts what it
// can find with high confidence and leaves everything else for the user
// to confirm in the form. Never throws: unparseable input yields an
// empty ScorecardScan.

class ScannedTee {
  final String name;
  final List<int> yards;

  /// Rating/slope printed on this tee box's own row, when the card gives
  /// every tee its own (common: the rating block sits at the end of each
  /// tee row rather than in one footer).
  final double? rating;
  final int? slope;

  /// Agreement with the yardage subtotals printed on this tee box's row.
  final SubtotalCheck subtotals;

  /// Holes whose yardage is impossible for the par (1-based hole numbers).
  final List<int> parMismatch;
  const ScannedTee({
    required this.name,
    required this.yards,
    this.rating,
    this.slope,
    this.subtotals = SubtotalCheck.none,
    this.parMismatch = const [],
  });

  /// True when this row is self-consistent *and* whole: 18 holes, every one
  /// of them actually read, no printed subtotal disagreeing, and no hole
  /// pairing an impossible yardage with its par.
  ///
  /// A row with a lost value reports no subtotals to check, and "no
  /// subtotals" must not read as "verified" — that is how a 16-hole row
  /// passes as good. Every hole has to be known for the same reason: a row
  /// placed by column always has 18 slots, so a hole that was never read
  /// shows up as a zero rather than as a shorter list, and length alone would
  /// wave it through.
  bool get verified =>
      yards.length >= 18 &&
      !yards.contains(0) &&
      subtotals.ok &&
      parMismatch.isEmpty;
}

class ScorecardScan {
  final List<int> pars;
  final List<ScannedTee> tees;
  final double? rating;
  final int? slope;

  /// Per-hole handicap (stroke index): 1..18, or 1..9 on a 9-hole card.
  final List<int> hcp;

  /// Agreement between the parsed par row and the par totals printed on it.
  final SubtotalCheck parSubtotals;
  const ScorecardScan({
    this.pars = const [],
    this.tees = const [],
    this.rating,
    this.slope,
    this.hcp = const [],
    this.parSubtotals = SubtotalCheck.none,
  });

  bool get isEmpty =>
      pars.isEmpty &&
      tees.isEmpty &&
      rating == null &&
      slope == null &&
      hcp.isEmpty;

  /// Tee boxes whose distances were confirmed against printed subtotals.
  int get verifiedTees => tees.where((t) => t.verified).length;
}

const _teeColors = [
  'BLACK',
  'BLUE',
  'WHITE',
  'GOLD',
  'RED',
  'GREEN',
  'SILVER',
  'YELLOW',
  'BRONZE',
];

/// Yardage window. The low end has to sit below the shortest real par 3
/// (cards print 80-95 yard par 3s) while still excluding handicap (1-18)
/// and par (3-5) values; the high end clears the longest par 5s but stays
/// under the OUT/IN/TOT subtotals, which are never below ~800 for nine
/// holes. An earlier 100..650 floor silently dropped short par 3s, and a
/// tee row that lost one of them also lost its whole back nine.
/// Shortest and longest a hole's yardage can be. A value outside this range is
/// not a yardage however it was read, so it is dropped rather than stored.
const int minYardage = 60;
const int maxYardage = 760;
const int _minYard = minYardage;
const int _maxYard = maxYardage;

const int _minRating = 55;
const int _maxRating = 85;
const int _minSlope = 55;
const int _maxSlope = 155;

/// Integers from [s], skipping any that are part of a decimal. Without this,
/// a rating of "70.4" would read as the yardage 70 and a pair like
/// "71.2/133" as three numbers.
List<int> _ints(String s) {
  final out = <int>[];
  var i = 0;
  bool digit(int c) => c >= 0x30 && c <= 0x39;
  while (i < s.length) {
    if (!digit(s.codeUnitAt(i))) {
      i++;
      continue;
    }
    var j = i;
    while (j < s.length && digit(s.codeUnitAt(j))) {
      j++;
    }
    final beforeDot = i > 0 && s.codeUnitAt(i - 1) == 0x2e;
    final dotDigit =
        j < s.length &&
        s.codeUnitAt(j) == 0x2e &&
        j + 1 < s.length &&
        digit(s.codeUnitAt(j + 1));
    if (!beforeDot && !dotDigit) out.add(int.parse(s.substring(i, j)));
    i = j;
  }
  return out;
}

/// First color word on the line, or null. Ties on position are impossible
/// (one word can only be one color), so the earliest mention wins.
String? _teeColor(String upperLine) {
  String? best;
  var bestPos = 1 << 30;
  for (final c in _teeColors) {
    final m = RegExp('\\b$c\\b').firstMatch(upperLine);
    if (m != null && m.start < bestPos) {
      bestPos = m.start;
      best = c;
    }
  }
  return best;
}

/// Words that can sit in front of "TEES" without being a tee name. "BACK"
/// and "FORWARD" are deliberately absent: they are ordinary tee names.
const _teeLabelStop = {
  'MEN',
  'WOMEN',
  'MENS',
  'LADIES',
  'GENTS',
  'HANDICAP',
  'HANDICAPS',
  'HCP',
  'HDCP',
  'PAR',
  'RATING',
  'SLOPE',
  'COURSE',
  'NAME',
  'HOLE',
  'STROKE',
  'INDEX',
  'SEE',
  'TEE',
  'TEES',
  'THE',
  'NO',
  'ALL',
  'TOTAL',
  'TIMES',
  'DETAILS',
  'INFO',
};

/// Uppercase label for the tee box a line belongs to, or null when the line
/// names none. Handles plain colors plus the "COMBO TEES" / "BACK TEE"
/// style, so tee boxes the color list does not know are still kept. A
/// color can appear anywhere ("O BLACK TEES"); any other name has to lead
/// the line, so prose that happens to contain "TEE" is not mistaken for a
/// tee box.
String? teeLabelFor(String upperLine) {
  final m = RegExp(
    r'([A-Z][A-Z/\-]*(?:[ ][A-Z][A-Z/\-]*)?)[ ]*TEES?\b',
  ).firstMatch(upperLine);
  if (m != null) {
    final phrase = m.group(1)!;
    final color = _teeColor(phrase);
    if (color != null) return color;
    if (m.start != 0) return _teeColor(upperLine);
    // Drop single-letter OCR debris in front of the name ("O BLACK").
    final words = phrase
        .split(RegExp(r'[ /-]+'))
        .where((w) => w.isNotEmpty && w.length > 1)
        .where((w) => !_teeLabelStop.contains(w))
        .toList();
    if (words.isEmpty || words.length > 2) return null;
    return words.join(' ');
  }
  return _teeColor(upperLine);
}

/// Lines carrying stroke-index/handicap data are never par or yardage data.
bool _isHcpLine(String upper) =>
    upper.contains('HCP') ||
    upper.contains('HDCP') ||
    upper.contains('HANDICAP') ||
    RegExp(r'\bSI\b').hasMatch(upper);

/// Word-boundary PAR, so a course or tee named "Park"/"Paradise" is not
/// mistaken for the par row.
bool _hasParLabel(String upper) => RegExp(r'\bPARS?\b').hasMatch(upper);

/// Column headers that mean the row is not a handicap ranking.
bool _isTotalHeader(String upper) =>
    RegExp(r'\b(OUT|IN|TOT|TOTAL|NET)\b').hasMatch(upper);

/// A "1 2 3 ... 18 OUT IN TOT" column header. A repeated one means the photo
/// holds a second block, which is a boundary: same-named tee rows from the
/// two blocks must not be merged into each other.
bool _isHoleHeader(String line, String upper) {
  if (!_isTotalHeader(upper)) return false;
  final nums = _ints(line);
  // Counted, not required: a trailing HCP/NET column is often misread as a
  // number above 27, and one bad value at the end must not throw away a
  // header that is otherwise a clean 1..18.
  return nums.where((n) => n >= 1 && n <= 27).length >= 9;
}

/// True when [nums] holds [n] distinct values inside 1..[max] — the shape
/// of a stroke index row ([n] == [max]) or of one half of one. For a full
/// row that is a permutation; for a nine-hole card it is the whole
/// ranking, and on an 18-hole card a nine-value row is only the front nine.
/// Also the shape of a "1 2 3 ... 18" hole-number header, so callers must
/// pair this with a label or a position next to the par row.
bool _distinctIn(List<int> nums, int n, int max) {
  if (nums.length != n) return false;
  final seen = <int>{};
  for (final v in nums) {
    if (v < 1 || v > max) return false;
    if (!seen.add(v)) return false;
  }
  return true;
}

/// True when [nums] is exactly 1..[max] once each.
bool _isPermutation(List<int> nums, int max) => _distinctIn(nums, max, max);

String _teeName(String label) =>
    '${label[0]}${label.substring(1).toLowerCase()}';

/// The display spelling of a tee label, shared by the text pass and the
/// column-geometry pass.
///
/// Both have to agree exactly: merging the two reads matches tee boxes by
/// name, so "RED" from one and "Red" from the other would be treated as two
/// different tees and both would reach the form.
String teeNameFrom(String label) => _teeName(label);

int _sum(List<int> v) => v.fold(0, (a, b) => a + b);

/// How a parsed row compares with the subtotals the card prints beside it.
/// Cards print OUT/IN/TOT (yardages) or front/total (par) in the same row,
/// so a row that disagrees with its own printed totals is provably misread
/// — worth telling the user, which is more useful than silently filling the
/// form with wrong numbers.
class SubtotalCheck {
  /// Front nine agrees with the printed OUT figure.
  final bool front;

  /// Back nine agrees with the printed IN figure (null for a 9-hole row).
  final bool? back;

  /// Whole row agrees with the printed TOT figure.
  final bool total;

  /// The row carried subtotals at all, so `front` means something.
  final bool printed;

  const SubtotalCheck({
    required this.front,
    required this.back,
    required this.total,
    required this.printed,
  });

  /// True when every printed subtotal that was present agrees.
  bool get ok => front && total && (back ?? true);

  static const none = SubtotalCheck(
    front: true,
    back: null,
    total: true,
    printed: false,
  );
}

/// Compares [row] with the subtotals in [printed] (every integer on the
/// source line that is not itself one of [row]'s values). Only exact
/// matches count, so a garbled subtotal reads as a disagreement rather than
/// a false confirmation.
SubtotalCheck checkSubtotals(List<int> row, List<int> printed) {
  if (row.isEmpty) return SubtotalCheck.none;
  // A hole that was not read makes every sum short by an unknown amount, so
  // there is nothing to compare against. "Cannot check" is the honest
  // answer, and it must not be reported as a passing check.
  if (row.contains(0)) return SubtotalCheck.none;
  final cells = printed.where((n) => !row.contains(n)).toSet();
  // A row that printed no subtotals gives nothing to check. A row that did
  // print them and matched none of them has *failed*, and saying so is the
  // whole value of the check: a misread row is otherwise indistinguishable
  // from a good one.
  if (cells.isEmpty) return SubtotalCheck.none;
  final total = _sum(row);
  final hasTotal = cells.contains(total);
  if (row.length >= 18) {
    final front = _sum(row.sublist(0, 9));
    final back = _sum(row.sublist(9, 18));
    return SubtotalCheck(
      front: cells.contains(front),
      back: cells.contains(back),
      total: hasTotal,
      printed: true,
    );
  }
  // A nine-hole row can only be checked against a total.
  return SubtotalCheck(
    front: hasTotal,
    back: null,
    total: hasTotal,
    printed: true,
  );
}

/// Holes whose yardage cannot belong to their par. A misread column order
/// or a dropped digit shows up here, which is the cheapest way to catch a
/// row that is internally consistent but attached to the wrong holes.
///
/// Checked per tee box, so the bounds have to suit the shortest tees: a
/// par 5 played from a forward tee is barely longer than a par 4 from the
/// back tee, and flagging those would cry wolf on every forward tee. The
/// bounds are deliberately loose because this is a prompt to re-check a
/// hole, not a reason to discard a row; a swapped column misses by hundreds
/// of yards.
List<int> parYardageMismatch(List<int> pars, List<int> yards) {
  final bad = <int>[];
  final n = pars.length < yards.length ? pars.length : yards.length;
  for (var i = 0; i < n; i++) {
    final y = yards[i];
    if (y == 0) continue;
    if (pars[i] == 3 && y > 280) bad.add(i + 1);
    if (pars[i] == 4 && y > 530) bad.add(i + 1);
    if (pars[i] == 5 && y < 370) bad.add(i + 1);
  }
  return bad;
}

typedef _Meta = ({double? rating, int? slope});

/// Rating/slope printed on a single tee box's row. A rating is a decimal,
/// so it is unambiguous; slope is only trusted when the card ties it to the
/// rating ("71.2/130", "SLOPE 130") or prints it directly after it. A bare
/// number is never taken as slope: in a yardage row it is a hole.
_Meta _rowMeta(String rawLine, List<int> yardages) {
  final up = rawLine.toUpperCase();
  double? rating;
  int? slope;

  final pair = RegExp(r'(\d{2}\.\d)\s*[/:]\s*(\d{2,3})').firstMatch(up);
  if (pair != null) {
    final r = double.tryParse(pair.group(1)!);
    final s = int.tryParse(pair.group(2)!);
    if (r != null &&
        r >= _minRating &&
        r <= _maxRating &&
        s != null &&
        s >= _minSlope &&
        s <= _maxSlope) {
      rating = r;
      slope = s;
    }
  }

  rating ??= (() {
    final m = RegExp(r'RATING\s*(\d{2}\.\d)').firstMatch(up);
    final r = m == null ? null : double.tryParse(m.group(1)!);
    return (r != null && r >= _minRating && r <= _maxRating) ? r : null;
  })();
  rating ??= (() {
    // Any decimal in range on a tee row is that tee box's rating.
    for (final m in RegExp(r'(?<!\d)(\d{2}\.\d)(?!\d)').allMatches(up)) {
      final r = double.tryParse(m.group(1)!);
      if (r != null && r >= _minRating && r <= _maxRating) return r;
    }
    return null;
  })();

  if (slope == null) {
    final m = RegExp(r'SLOPE\D{0,4}(\d{2,3})\b').firstMatch(up);
    final s = m == null ? null : int.tryParse(m.group(1)!);
    if (s != null && s >= _minSlope && s <= _maxSlope) slope = s;
  }
  if (slope == null && rating != null) {
    // "70.4 118": the number directly after the rating, as long as it is
    // not one of the row's own yardages.
    final m = RegExp(r'(?<!\d)(\d{2}\.\d)(?!\d)').firstMatch(up);
    if (m != null) {
      final after = _ints(up.substring(m.end));
      if (after.isNotEmpty) {
        final n = after.first;
        if (n >= _minSlope && n <= _maxSlope && !yardages.contains(n)) {
          slope = n;
        }
      }
    }
  }
  return (rating: rating, slope: slope);
}

ScorecardScan parseScorecardText(String text) {
  final rawLines = text
      .split(RegExp(r'\r?\n'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  // OCR often runs several table rows together on one line. A single tee
  // row holds at most 18 holes (+OUT/IN/TOT), so a line with 36+ yardage
  // numbers is really multiple tee boxes: split into 18-number virtual
  // lines (first keeps the color label, the rest are unnamed) instead of
  // silently keeping only the first tee.
  final lines = <String>[];
  final virtual = <int>{};
  for (final l in rawLines) {
    final nums = _ints(l).where((n) => n >= _minYard && n <= _maxYard).toList();
    if (nums.length < 36) {
      lines.add(l);
      continue;
    }
    var first = true;
    for (var s = 0; s < nums.length; s += 18) {
      final chunk = nums.skip(s).take(18).toList();
      if (chunk.length < 9) break;
      if (!first) virtual.add(lines.length);
      lines.add(first ? l : chunk.join(' '));
      first = false;
    }
  }
  final uppers = lines.map((l) => l.toUpperCase()).toList();
  List<int> parNums(int i) =>
      _ints(lines[i]).where((n) => n >= 3 && n <= 5).toList();
  List<int> yardNums(int i) =>
      _ints(lines[i]).where((n) => n >= _minYard && n <= _maxYard).toList();

  // Par row: a line mentioning PAR with numbers in 3..5, or — when OCR ate
  // the label — any line whose every number is a par value (yardages are
  // 60+, handicaps 1-18, so shape alone is safe). Real cards print the
  // front-nine par total between the nines, so a value equal to the running
  // total is dropped before the rest of the line is appended. A row is
  // assembled across following lines (front/back split, or a row read as
  // 6+6+6); a *labelled* PAR line always starts a new row, so a second
  // block on the same photo can never be appended to the first.
  var pars = <int>[];
  var parSubtotals = SubtotalCheck.none;
  final parLines = <int>{};
  var cur = <int>[];
  var curAll = <int>[];
  final curLines = <int>{};

  bool usablePar(int len) =>
      (len == 18 && _sum(cur) >= 50 && _sum(cur) <= 80) ||
      (len == 9 && _sum(cur) >= 24 && _sum(cur) <= 42);

  void finishPar() {
    if ((cur.length == 9 || cur.length == 18) &&
        cur.length > pars.length &&
        usablePar(cur.length)) {
      pars = List.of(cur);
      parLines
        ..clear()
        ..addAll(curLines);
      parSubtotals = checkSubtotals(cur, curAll);
    }
    cur = <int>[];
    curAll = <int>[];
    curLines.clear();
  }

  for (var i = 0; i < lines.length; i++) {
    if (_isHcpLine(uppers[i]) || teeLabelFor(uppers[i]) != null) continue;
    final all = _ints(lines[i]);
    final labeled = _hasParLabel(uppers[i]);
    final shape = all.length >= 3 && all.every((n) => n >= 3 && n <= 5);
    // Unlabelled chunks are only trusted directly after a par line, and
    // only while a row is still short.
    final continuation =
        !labeled &&
        cur.isNotEmpty &&
        cur.length < 18 &&
        i > 0 &&
        curLines.contains(i - 1);
    if (!labeled && !shape && !continuation) continue;
    if (labeled && cur.isNotEmpty) finishPar();
    if (cur.isEmpty && !labeled && !shape) continue;
    if (cur.length + parNums(i).length > 18) finishPar();
    // The printed front-nine total sits between the nines, not as a par.
    final running = cur.isEmpty ? -1 : _sum(cur);
    final chunk = parNums(i).where((n) => n != running).toList();
    if (chunk.isEmpty || chunk.length > 18 - cur.length) continue;
    cur = [...cur, ...chunk];
    curAll = [...curAll, ...all];
    curLines.add(i);
  }
  finishPar();

  // Stroke index ("HCP"/"HANDICAP" row): eighteen values covering 1..18
  // once each, so a bad read is rejected outright. A hole-number header
  // has the same shape, so rows are only taken when they are labeled as a
  // handicap or sit within two lines of the par row, and never when they
  // carry OUT/IN/TOT column headers. A nine-value row is the whole ranking
  // on a 9-hole card, and the front nine on an 18-hole card, where it is
  // only usable if the next line supplies the back nine. Men's and women's
  // blocks both appear on many cards; men's wins, as the index of record.
  var hcp = <int>[];
  final hcpLines = <int>{};
  var hcpRank = 0;
  for (var i = 0; i < lines.length; i++) {
    if (parLines.contains(i) || hcpLines.contains(i)) continue;
    if (_isTotalHeader(uppers[i])) continue;
    if (yardNums(i).length >= 9) continue;
    final nums = _ints(lines[i]);
    final labeled = _isHcpLine(uppers[i]);
    if (!labeled && !parLines.any((p) => (p - i).abs() <= 2)) continue;
    final rank = RegExp(r'WOMEN|LADIES').hasMatch(uppers[i]) ? 1 : 2;

    var row = <int>[];
    var used = <int>[i];
    if (_isPermutation(nums, 18)) {
      row = nums;
    } else if (_distinctIn(nums, 9, 18)) {
      // Front nine here, back nine on the next line.
      final nxt = i + 1 < lines.length ? i + 1 : -1;
      if (pars.length != 9 &&
          nxt >= 0 &&
          !parLines.contains(nxt) &&
          !hcpLines.contains(nxt) &&
          yardNums(nxt).length < 9 &&
          !_isTotalHeader(uppers[nxt])) {
        final more = _ints(lines[nxt]);
        if (_isPermutation([...nums, ...more], 18)) {
          row = [...nums, ...more];
          used = [i, nxt];
        }
      }
      if (row.isEmpty && pars.length == 9 && _isPermutation(nums, 9)) {
        row = nums;
      }
    }
    if (row.isEmpty) continue;
    if (rank < hcpRank) continue;
    if (rank == hcpRank && hcp.length >= row.length) continue;
    hcp = row;
    hcpRank = rank;
    hcpLines
      ..clear()
      ..addAll(used);
  }
  // Nine values cannot drive an 18-hole round; the form falls back to the
  // odd/even estimate there.
  if (hcp.length == 9 && pars.length == 18) hcp = <int>[];

  // Yardage rows: 9+ numbers in the yardage window; tee label from the same
  // line. Front/back splits (9 numbers now, 9 more on the next plain line)
  // and repeated same-name rows are merged so every tee box ends up whole.
  //
  // Three rescues for real OCR output:
  // * Standalone color labels ("BLUE" on its own line, or a "BLUE 72.1/130"
  //   header with no yardages) are carried onto the next numbered line,
  //   along with the rating/slope they carry.
  // * Labeled fragments shorter than 9 numbers (a row OCR read as 6+6+6,
  //   etc.) append per label; same-name chunks merge and short rows never
  //   surface. Single-number lines are rating/slope metadata, not chunks.
  // * A rating/slope pair printed in front of or behind the yardages is
  //   dropped, so the hole count still lines up with the row.
  final labels = List<String?>.filled(lines.length, null);
  final carried = List<_Meta?>.filled(lines.length, null);
  String? carry;
  _Meta? carryMeta;
  for (var i = 0; i < lines.length; i++) {
    if (parLines.contains(i) || hcpLines.contains(i)) continue;
    final label = teeLabelFor(uppers[i]);
    final nums = yardNums(i);
    if (label != null && nums.length < 9) {
      carry = label;
      carryMeta = _rowMeta(lines[i], nums);
      continue;
    }
    if (nums.isNotEmpty && carry != null) {
      labels[i] = carry;
      carried[i] = carryMeta;
      carry = null;
      carryMeta = null;
    }
  }

  // A card can print two blocks (men's and women's) in one photo, and both
  // may list a tee of the same name. Lines that start a block — a par row
  // or a repeated hole-number header — bump [blockAt], so a later block's
  // "BLACK" replaces an earlier partial "BLACK" instead of being appended
  // to it and fusing two different rows into one bogus tee box.
  final blockAt = List<int>.filled(lines.length, 0);
  var block = 0;
  var sawHeader = -1;
  for (var i = 0; i < lines.length; i++) {
    if (parLines.contains(i)) {
      block++;
      sawHeader = -1;
    } else if (_isHoleHeader(lines[i], uppers[i])) {
      // A second header means a second block; the first one is not.
      if (sawHeader >= 0) block++;
      sawHeader = i;
    }
    blockAt[i] = block;
  }

  final teeYards = <String, List<int>>{};
  final teeMeta = <String, _Meta>{};
  final teeSubtotals = <String, SubtotalCheck>{};
  final teeBlock = <String, int>{};
  final teeOrder = <String>[];
  var unnamed = 0;
  void addYards(
    String name,
    List<int> nums, {
    _Meta? meta,
    SubtotalCheck? subtotals,
    int block = 0,
    bool replace = false,
  }) {
    final existing = teeYards[name];
    if (existing == null) {
      teeOrder.add(name);
      teeYards[name] = <int>[];
      teeBlock[name] = block;
    } else if (replace) {
      // Different card block: keep the newest row, not a mixture.
      existing.clear();
      teeBlock[name] = block;
      teeSubtotals.remove(name);
    }
    final cur = teeYards[name]!;
    for (final n in nums) {
      if (cur.length >= 18) break;
      cur.add(n);
    }
    if (meta != null) {
      final prev = teeMeta[name];
      if (prev == null || (prev.rating == null && meta.rating != null)) {
        teeMeta[name] = meta;
      }
    }
    if (subtotals != null &&
        (subtotals.printed || teeSubtotals[name] == null)) {
      teeSubtotals[name] = subtotals;
    }
  }

  final consumed = <int>{};
  // Row currently being assembled from fragments, so a following bare
  // number line can be recognized as its continuation.
  String? fragmentName;
  var fragmentLast = -1;
  for (var i = 0; i < lines.length; i++) {
    if (consumed.contains(i)) continue;
    if (parLines.contains(i) ||
        hcpLines.contains(i) ||
        _hasParLabel(uppers[i]) ||
        _isHcpLine(uppers[i])) {
      continue;
    }
    final label = teeLabelFor(uppers[i]) ?? labels[i];
    final raw = yardNums(i);
    final nums = _stripRowMetadata(raw);
    if (nums.length < 9) {
      // Fragment of a labeled row ("BLACK 366 374 200" then three more
      // bare number lines). Chunks are appended per label, and a chunk with
      // no label of its own is taken as the continuation of the row above
      // it — on a real card every yardage row is labeled, so a bare number
      // line directly under a half-read row belongs to that row. Same-name
      // chunks merge and short rows never surface. Single-number lines are
      // rating/slope metadata, not chunks.
      // A chunk counts as a continuation when it names the row already in
      // progress (either with its own label or with one carried down from
      // the line above), sits on the very next line, and that row is still
      // short. Any other bare number line is left alone.
      final name = label == null
          ? fragmentName
          : (nums.length >= 2 ? _teeName(label) : null);
      final carriedOn = teeYards[name]?.length ?? 0;
      final continues =
          name != null &&
          name == fragmentName &&
          i == fragmentLast + 1 &&
          blockAt[i] == blockAt[fragmentLast] &&
          carriedOn > 0 &&
          carriedOn < 18;
      if (name == null || nums.length < 2 || (carriedOn > 0 && !continues)) {
        fragmentName = null;
        continue;
      }
      addYards(name, nums, meta: carried[i], block: blockAt[i]);
      fragmentName = name;
      fragmentLast = i;
      continue;
    }
    fragmentName = null;
    // Keep the row whole. A line holding more than nine numbers is one
    // row, even when a digit or two was lost: taking only the first nine
    // would throw away the back nine, and taking 18 unconditionally would
    // eat the next line's start on a genuine front/back split.
    var row = nums.take(nums.length > 9 ? 18 : nums.length).toList();
    // Split-line chunks never merge: their neighbors belong to other rows.
    if (row.length == 9 &&
        !virtual.contains(i) &&
        i + 1 < lines.length &&
        !consumed.contains(i + 1) &&
        !virtual.contains(i + 1) &&
        !parLines.contains(i + 1) &&
        !hcpLines.contains(i + 1) &&
        blockAt[i + 1] == blockAt[i]) {
      final nxtNums = _stripRowMetadata(yardNums(i + 1));
      if (nxtNums.length >= 9 &&
          !_isHcpLine(uppers[i + 1]) &&
          !_hasParLabel(uppers[i + 1]) &&
          teeLabelFor(uppers[i + 1]) == null &&
          labels[i + 1] == null) {
        row = [...row, ...nxtNums.take(9)];
        consumed.add(i + 1);
      }
    }
    final own = _rowMeta(lines[i], row);
    final inherited = carried[i];
    final meta = (
      rating: own.rating ?? inherited?.rating,
      slope: own.slope ?? inherited?.slope,
    );
    // A value outside the yardage window is not this hole's yardage: a
    // misread like 986 for 286 says nothing about hole 1, so the hole is
    // dropped rather than kept as an impossible length.
    //
    // Note that a value dropped here still shifts the row: in reading order
    // the holes after the gap are one place off. The card's own OUT/IN/TOT
    // subtotals are what catch that, and the par inferred from the tee boxes
    // that did read in full is what recovers the par row. Placing each value
    // under its own column would fix the shift directly, but the text alone
    // does not carry column geometry — see the note on readColumns' removal.
    for (var c = 0; c < row.length; c++) {
      if (row[c] < _minYard || row[c] > _maxYard) row[c] = 0;
    }
    var placed = row;
    final name = label == null ? 'Tee ${++unnamed}' : _teeName(label);
    final prevBlock = teeBlock[name];
    final prevLen = teeYards[name]?.length ?? 0;
    final blockDiffers = prevBlock != null && prevBlock != blockAt[i];
    fragmentName = null;
    // A tee that already has all 18 distances gains nothing from another
    // row, and re-checking it against that row's subtotals would replace a
    // real verification with a meaningless one. The one exception is a
    // complete row from a later block: same name, different card block, so
    // the earlier one is incomplete by definition.
    if (prevLen >= 18 && !(blockDiffers && row.length == 18)) continue;
    addYards(
      name,
      placed,
      meta: meta,
      subtotals: checkSubtotals(placed, _ints(lines[i])),
      block: blockAt[i],
      replace: blockDiffers,
    );
  }
  final rowTees = [
    for (final name in teeOrder)
      if (teeYards[name]!.length >= 9)
        ScannedTee(
          name: name,
          yards: teeYards[name]!,
          rating: teeMeta[name]?.rating,
          slope: teeMeta[name]?.slope,
          subtotals: teeSubtotals[name] ?? SubtotalCheck.none,
          parMismatch: parYardageMismatch(pars, teeYards[name]!),
        ),
  ];
  // Column-wise fallback: OCR sometimes reads tables top-to-bottom, giving
  // one line per hole ("1 402 380 350 ..."). Row parsing finds nothing
  // useful then, so transpose hole-lines into tees instead.
  final colTees = rowTees.length < 2 ? _columnTees(lines) : <ScannedTee>[];
  final tees = colTees.length >= 2 ? colTees : rowTees;

  // Rating/slope: "71.2/130", "71.2 : 135", or RATING/SLOPE keywords.
  double? rating;
  int? slope;
  final upper = text.toUpperCase();
  final pair = RegExp(r'(\d{2}\.\d)\s*[/:]\s*(\d{2,3})').firstMatch(upper);
  if (pair != null) {
    final r = double.tryParse(pair.group(1)!);
    final s = int.tryParse(pair.group(2)!);
    if (r != null &&
        r >= _minRating &&
        r <= _maxRating &&
        s != null &&
        s >= _minSlope &&
        s <= _maxSlope) {
      rating = r;
      slope = s;
    }
  }
  rating ??= (() {
    final m = RegExp(r'RATING\s*(\d{2}\.\d)').firstMatch(upper);
    final r = m == null ? null : double.tryParse(m.group(1)!);
    return (r != null && r >= _minRating && r <= _maxRating) ? r : null;
  })();
  rating ??= (() {
    // Bare rating with no slope and no RATING word, as in "6323 70.4 -".
    // A standalone decimal in range is the course rating; yardages,
    // handicaps and pars are integers, so this does not misfire on them.
    for (final m in RegExp(r'(?<!\d)(\d{2}\.\d)(?!\d)').allMatches(text)) {
      final r = double.tryParse(m.group(1)!);
      if (r != null && r >= _minRating && r <= _maxRating) return r;
    }
    return null;
  })();
  slope ??= (() {
    final m = RegExp(r'SLOPE\s*(\d{2,3})').firstMatch(upper);
    final s = m == null ? null : int.tryParse(m.group(1)!);
    return (s != null && s >= _minSlope && s <= _maxSlope) ? s : null;
  })();
  // Nothing above matched, but a tee row may still have carried one.
  if (rating == null && tees.isNotEmpty) rating = tees.first.rating;
  if (slope == null && tees.isNotEmpty) slope = tees.first.slope;

  return ScorecardScan(
    pars: pars,
    tees: tees,
    rating: rating,
    slope: slope,
    hcp: hcp,
    parSubtotals: parSubtotals,
  );
}

/// Drops a rating/slope pair that a tee row printed in front of or behind
/// its yardages ("BLUE 71.2/133 402 515 ..."), which would otherwise shift
/// every hole by one. Only applied when the row holds more than 18 numbers,
/// so a genuine 18-hole row is never touched.
List<int> _stripRowMetadata(List<int> nums) {
  if (nums.length <= 18) return nums;
  // Rating (55-85) and slope (55-155) both land inside the yardage window;
  // in rating/slope range the two overlap, so one bound covers both.
  bool meta(int n) => n >= _minRating && n <= _maxSlope;
  final extra = nums.length - 18;
  if (nums.take(extra).every(meta)) return nums.skip(extra).toList();
  if (nums.sublist(nums.length - extra).every(meta)) {
    return nums.sublist(0, nums.length - extra);
  }
  return nums;
}

/// Scores a parse for the PSM retry ensemble: whole tee rows weigh most,
/// then the par row, then rating/slope and the handicap row. Higher is
/// better; ties keep the earlier read, so callers only replace on strict
/// improvement.
int scanQuality(ScorecardScan s) {
  var q = 0;
  for (final t in s.tees) {
    final n = t.yards.length;
    if (n >= 18) {
      q += 100 + n;
    } else if (n >= 9) {
      q += n;
    }
    if (t.rating != null) q += 4;
    if (t.slope != null) q += 4;
  }
  if (s.pars.length == 18) {
    q += 50;
  } else if (s.pars.length == 9) {
    q += 20;
  }
  if (s.rating != null) q += 5;
  if (s.slope != null) q += 5;
  if (s.hcp.length == 18) {
    q += 25;
  } else if (s.hcp.length == 9) {
    q += 10;
  }
  return q;
}

/// True when a parse is solid enough to skip further PSM attempts:
/// at least two usable tee rows plus a par row.
bool scanGoodEnough(ScorecardScan s) =>
    s.tees.where((t) => t.yards.length >= 9).length >= 2 && s.pars.length >= 9;

/// True when [hcp] is a usable stroke index for [holes] holes.
bool validStrokeIndexes(List<int> hcp, int holes) => _isPermutation(hcp, holes);

/// Transpose hole-per-line OCR output into tees. Returns [] unless at
/// least 9 lines look like "hole-number followed by 3+ yardages" with hole
/// numbers starting at 1 (a par-first misread like "4 402 ..." fails).
/// Columns are named from a color legend on the card when one matches the
/// column count, otherwise they stay "Tee 1..n".
List<ScannedTee> _columnTees(List<String> lines) {
  final byHole = <int, List<int>>{};
  for (final line in lines) {
    final m = RegExp(r'^\s*(\d{1,2})\b(.*)$').firstMatch(line);
    if (m == null) continue;
    final hole = int.parse(m.group(1)!);
    if (hole < 1 || hole > 27) continue;
    final nums = _ints(
      m.group(2)!,
    ).where((n) => n >= _minYard && n <= _maxYard).toList();
    if (nums.length < 3) continue;
    byHole.putIfAbsent(hole, () => nums);
  }
  if (byHole.length < 9) return [];
  final keys = byHole.keys.toList()..sort();
  if (keys.first != 1) return [];
  if (keys.last - keys.first + 1 - keys.length > 2) return [];
  final width = byHole.values
      .map((v) => v.length)
      .reduce((a, b) => a < b ? a : b);
  if (width < 3) return [];
  final use = keys.take(18).toList();
  final names = _columnNames(lines, width);
  return List.generate(
    width,
    (j) =>
        ScannedTee(name: names[j], yards: [for (final h in use) byHole[h]![j]]),
  );
}

/// Tee names for column-wise reads, taken from a legend line that lists
/// exactly [width] color names in order ("BLACK BLUE WHITE RED"). Any other
/// line, or a count mismatch, leaves the generic "Tee n" names in place.
List<String> _columnNames(List<String> lines, int width) {
  final generic = [for (var j = 0; j < width; j++) 'Tee ${j + 1}'];
  for (final line in lines) {
    final found = RegExp(r'[A-Z]+')
        .allMatches(line.toUpperCase())
        .map((m) => m.group(0)!)
        .where(_teeColors.contains)
        .toList();
    // Distinct, in order, and no repeats: a legend, not a passing mention.
    if (found.length == width && found.toSet().length == width) {
      return found.map(_teeName).toList();
    }
  }
  return generic;
}

/// Combines several reads of the same card into one result, taking each
/// field from whichever read got it right.
///
/// OCR attempts fail independently: one pass may nail the yardages but lose
/// the small print, the next the reverse. Ranking whole parses against a
/// single score throws that away — a read with five tee boxes and no par
/// outscores a read with four tees and par, so the user loses the par they
/// were after. Merging per field keeps every read's successes.
///
/// Yardages are never blended between reads: a tee box is taken whole from
/// the single best read of it, because mixing values from different passes
/// produces a row that is wrong in a way neither pass was.
ScorecardScan mergeScans(List<ScorecardScan> scans) {
  if (scans.isEmpty) return const ScorecardScan();
  if (scans.length == 1) return scans.first;

  // Par: the longest row wins, and a row that agrees with the printed par
  // total beats one that does not.
  var pars = <int>[];
  var parSubtotals = SubtotalCheck.none;
  for (final s in scans) {
    if (s.pars.length < pars.length) continue;
    if (s.pars.length == pars.length &&
        !(s.parSubtotals.ok && !parSubtotals.ok)) {
      continue;
    }
    pars = s.pars;
    parSubtotals = s.parSubtotals;
  }

  // Tee boxes: best read of each name, ordered by the read that saw it first
  // so the card's own top-to-bottom tee order survives.
  final best = <String, ScannedTee>{};
  final order = <String>[];
  for (final s in scans) {
    for (final t in s.tees) {
      final prior = best[t.name];
      if (prior == null) {
        order.add(t.name);
        best[t.name] = t;
        continue;
      }
      if (_teeRank(t) > _teeRank(prior)) best[t.name] = t;
    }
  }

  // Card-wide rating/slope: from a read whose own tees verified, since a
  // rating read off a garbled line is not worth preferring.
  double? rating;
  int? slope;
  for (final s in [
    ...scans,
  ]..sort((a, b) => b.verifiedTees.compareTo(a.verifiedTees))) {
    rating ??= s.rating;
    slope ??= s.slope;
  }

  // Handicap: a full permutation, or the front nine on a 9-hole card.
  List<int> hcp = const [];
  for (final s in scans) {
    if (s.hcp.length <= hcp.length) continue;
    hcp = s.hcp;
  }

  // A tee row is only meaningful next to a par, and the par it was checked
  // against is whichever one that pass happened to read — which, in exactly
  // the case that needs merging, was no par at all. Recheck every tee against
  // the par that was kept, so a row that only makes sense with a different
  // par is reported rather than passed off as verified.
  final tees = [
    for (final n in order)
      ScannedTee(
        name: best[n]!.name,
        yards: best[n]!.yards,
        rating: best[n]!.rating,
        slope: best[n]!.slope,
        subtotals: best[n]!.subtotals,
        parMismatch: pars.isEmpty
            ? const <int>[]
            : parYardageMismatch(pars, best[n]!.yards),
      ),
  ];

  return ScorecardScan(
    pars: pars,
    tees: tees,
    rating: rating,
    slope: slope,
    hcp: hcp,
    parSubtotals: parSubtotals,
  );
}

/// How much a single tee-box read can be trusted: whole first, then rows
/// that agree with their printed totals.
///
/// Deliberately blind to [ScannedTee.parMismatch]. A read that saw no par row
/// has nothing to check a hole against, so its mismatch list is empty for the
/// wrong reason, and ranking on it would prefer whichever pass happened to
/// guess a par. The merged par is the one that counts, so the check is redone
/// in [mergeScans] once the par is known.
int _teeRank(ScannedTee t) {
  var rank = t.yards.length >= 18 ? 1000 : t.yards.length * 10;
  if (t.subtotals.printed) rank += t.subtotals.ok ? 100 : 0;
  if (t.rating != null) rank += 5;
  if (t.slope != null) rank += 5;
  return rank;
}

/// Par read off the card, or proposed from the yardages when the par row
/// itself was too small to survive the photo.
class ParProposal {
  /// Proposed par for each hole.
  final List<int> pars;

  /// Holes the yardages alone force. False means "a reasonable guess the
  /// user should confirm", which is a hole whose yardage sits where a par 4
  /// and a par 5 are genuinely hard to tell apart.
  final List<bool> certain;

  /// Printed par total the proposal was reconciled against, if the card
  /// gave one and it was readable.
  final int? total;

  /// How many of the uncertain holes must be 5s to add up to [total]. The
  /// total pins down the count but not which holes, so the user picks those.
  final int? fivesNeeded;

  ParProposal({
    required this.pars,
    required this.certain,
    this.total,
    this.fivesNeeded,
  });

  List<int> get uncertainHoles => [
    for (var i = 0; i < certain.length; i++)
      if (!certain[i]) i + 1,
  ];
}

/// Proposes par for each hole from the yardages on the card.
///
/// The par row is the smallest print on a scorecard, so it is the first
/// thing a bad photo loses, while the yardage rows — bigger, and repeated
/// once per tee box — usually survive. That makes the yardages the better
/// source: a hole that is short from *every* tee box is a par 3, and one
/// that is long from every tee box is very likely a par 5, whatever the
/// par row managed to say.
///
/// A par 3 and a par 4 are well separated (the longest par 3 on a real
/// course is around 280 yards, the shortest par 4 over 300), so short holes
/// are certain. A par 4 and a par 5 genuinely overlap around 400-440 yards,
/// so holes in that band are reported as uncertain rather than guessed
/// silently. When the card's own par total was read, it is used to say how
/// many of the uncertain holes are 5s.
ParProposal? inferParFromYardages(
  List<List<int>> tees, {
  int? total,
  List<int> partialPars = const [],
}) {
  // One value per hole from the longest tee box: a par 3 stays short and a
  // par 5 stays long even measured from the longest set of tees.
  //
  // Only whole rows count. A row that lost a digit has every value after the
  // gap shifted one hole left, and using it would move a short par 3 onto
  // the wrong hole — the one mistake this cannot recover from, because it
  // would then vote for a par 4.
  final whole = [
    for (final t in tees)
      if (t.length >= 18) t,
  ];
  if (whole.isEmpty) return null;
  final holes = <int>[];
  for (var i = 0; i < 18; i++) {
    var longest = 0;
    for (final t in whole) {
      // 0 means that tee box did not read this hole; it must not be treated
      // as a zero-yard hole, which would vote for a par 3.
      if (t[i] > longest) longest = t[i];
    }
    holes.add(longest);
  }
  if (holes.every((y) => y == 0)) return null;

  final pars = <int>[];
  final certain = <bool>[];
  for (var i = 0; i < holes.length; i++) {
    final y = holes[i];
    // A par value actually read off the card wins over the guess, unless it
    // is one of the digit/letter confusions this whole fallback exists for
    // (5 read as 7, 3 read as 8).
    final read = i < partialPars.length ? partialPars[i] : 0;
    if (read >= 3 && read <= 5) {
      pars.add(read);
      certain.add(y <= _certainThree || y >= _fiveHigh);
      continue;
    }
    if (y == 0) {
      // No tee box managed this hole, so there is nothing to go on.
      pars.add(4);
      certain.add(false);
    } else if (y <= _certainThree) {
      pars.add(3);
      certain.add(true);
    } else if (y < _fiveLow) {
      pars.add(4);
      certain.add(true);
    } else if (y < _fiveHigh) {
      // Where a par 4 and a par 5 are indistinguishable by length.
      pars.add(4);
      certain.add(false);
    } else {
      pars.add(5);
      certain.add(true);
    }
  }

  int? fivesNeeded;
  if (total != null) {
    final fixed = <int>[];
    for (var i = 0; i < pars.length; i++) {
      if (certain[i]) fixed.add(pars[i]);
    }
    final base = fixed.fold(0, (a, b) => a + b);
    final unknown = pars.length - fixed.length;
    // The uncertain holes start as 4s; each 5 adds one.
    final k = total - base - 4 * unknown;
    if (k >= 0 && k <= unknown) {
      fivesNeeded = k;
      // Spend them on the longest uncertain holes, which are the most likely
      // 5s, so the proposal is ordered by plausibility rather than by hole.
      final order = <int>[
        for (var i = 0; i < pars.length; i++)
          if (!certain[i]) i,
      ]..sort((a, b) => holes[b].compareTo(holes[a]));
      for (var j = 0; j < k && j < order.length; j++) {
        pars[order[j]] = 5;
      }
    }
  }
  return ParProposal(
    pars: pars,
    certain: certain,
    total: total,
    fivesNeeded: fivesNeeded,
  );
}

/// At or below this a hole is a par 3 from any tee box (the longest par 3
/// in professional golf is about 280 yards).
const int _certainThree = 285;

/// Between [_fiveLow] and [_fiveHigh] a par 4 and a par 5 are not
/// distinguishable by length, so the hole is asked about rather than guessed.
const int _fiveLow = 400;
const int _fiveHigh = 445;

/// The course par total printed on the par row, if the row was read well
/// enough to show its total even though the per-hole values were not.
///
/// Worth looking for on its own: a card whose par values OCR turned into
/// letters often still shows "71" at the end of the row, and that one number
/// is what lets the par guessed from the yardages be checked against the
/// card instead of taken on trust.
///
/// A row is taken to be the par row when it is labelled as one, or — after a
/// digits-only pass, which throws the labels away — when it is a run of
/// values in 3..5 with a plausible course total sitting at the end of it.
/// The par row is the only place a scorecard prints a long run of single
/// digits followed by a number in the 50s, so a false match needs a card
/// layout that does something stranger than that.
int? printedParTotal(String text) {
  for (final line in text.split('\n')) {
    final upper = line.toUpperCase();
    final numbers = _ints(line);
    final labelled = _hasParLabel(upper);
    if (!labelled) {
      // Digits-only pass: the row still has the right shape even though
      // "PAR" is now a blank.
      final pars = numbers.where((n) => n >= 3 && n <= 5).length;
      if (pars < 9) continue;
    }
    for (final n in numbers.reversed) {
      if (n >= 50 && n <= 80) return n;
    }
  }
  return null;
}

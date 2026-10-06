import 'whs.dart' as whs;

class HoleInfo {
  final int number;
  final int par;
  final int yardage;
  final int? strokeIndex;
  final double lat;
  final double lon;
  const HoleInfo({
    required this.number,
    required this.par,
    required this.yardage,
    this.strokeIndex,
    this.lat = 0,
    this.lon = 0,
  });

  Map<String, dynamic> toJson() => {
    'number': number,
    'par': par,
    'yardage': yardage,
    'strokeIndex': strokeIndex,
    'lat': lat,
    'lon': lon,
  };

  static HoleInfo fromJson(Map<String, dynamic> j) => HoleInfo(
    number: (j['number'] as num).toInt(),
    par: (j['par'] as num).toInt(),
    yardage: (j['yardage'] as num).toInt(),
    strokeIndex: (j['strokeIndex'] as num?)?.toInt(),
    lat: (j['lat'] as num?)?.toDouble() ?? 0,
    lon: (j['lon'] as num?)?.toDouble() ?? 0,
  );
}

class Tee {
  final String id;
  final String name;

  /// Overall rating for this tee, or the 9-hole rating when [holes] has nine.
  final double rating;

  /// Overall slope for this tee, or the 9-hole slope when [holes] has nine.
  final int slope;

  /// Published ratings for each nine of an 18-hole tee, when known.
  final double? frontNineRating;
  final int? frontNineSlope;
  final double? backNineRating;
  final int? backNineSlope;
  final List<HoleInfo> holes;
  const Tee({
    required this.id,
    required this.name,
    required this.rating,
    required this.slope,
    this.frontNineRating,
    this.frontNineSlope,
    this.backNineRating,
    this.backNineSlope,
    required this.holes,
  });

  int get par => holes.fold(0, (s, h) => s + h.par);
  int get yardage => holes.fold(0, (s, h) => s + h.yardage);

  /// Pars for a stretch of holes, e.g. one nine of an 18-hole tee.
  ///
  /// [start] is a 0-based hole index and [count] how many holes to cover.
  /// Missing holes fall back to par 4, so a tee edited down to 9 holes still
  /// yields a full-length list instead of throwing on the back nine.
  List<int> parsFrom(int start, int count) => [
    for (var i = start; i < start + count; i++)
      (i >= 0 && i < holes.length) ? holes[i].par : 4,
  ];

  /// Total par for a stretch of holes, from [parsFrom].
  int parTotalFrom(int start, int count) =>
      parsFrom(start, count).fold(0, (s, p) => s + p);

  ({double rating, int slope})? nineHoleRatings(int startHole) {
    final (rating, slope) = switch ((holes.length, startHole)) {
      (9, 0) => (this.rating, this.slope),
      (18, 0) => (frontNineRating, frontNineSlope),
      (18, 9) => (backNineRating, backNineSlope),
      _ => (null, null),
    };
    if (rating == null ||
        slope == null ||
        !rating.isFinite ||
        rating < 20 ||
        rating > 45 ||
        slope < 55 ||
        slope > 155) {
      return null;
    }
    return (rating: rating, slope: slope);
  }

  int? courseHandicapForRound({
    required int holesPlayed,
    required int startHole,
    required double handicapIndex,
  }) {
    if (holesPlayed == 9) {
      final ratings = nineHoleRatings(startHole);
      if (ratings == null) return null;
      return whs.nineHoleCourseHandicap(
        handicapIndex: handicapIndex,
        slopeRating: ratings.slope.toDouble(),
        courseRating: ratings.rating,
        par: parTotalFrom(startHole, 9),
      );
    }
    if (holes.length != 18 ||
        startHole != 0 ||
        holesPlayed < 10 ||
        holesPlayed > 18) {
      return null;
    }
    return whs.courseHandicap(
      handicapIndex: handicapIndex,
      slopeRating: slope.toDouble(),
      courseRating: rating,
      par: par,
    );
  }

  /// Unrounded Course Handicap for the same selection as
  /// [courseHandicapForRound], so a Playing Handicap panel can apply the
  /// allowances before rounding rather than round the rounded Course Handicap.
  double? unroundedCourseHandicapForRound({
    required int holesPlayed,
    required int startHole,
    required double handicapIndex,
  }) {
    if (holesPlayed == 9) {
      final ratings = nineHoleRatings(startHole);
      if (ratings == null) return null;
      final half = (handicapIndex / 2 * 10).round() / 10.0;
      return whs.unroundedCourseHandicap(
        handicapIndex: half,
        slopeRating: ratings.slope.toDouble(),
        courseRating: ratings.rating,
        par: parTotalFrom(startHole, 9),
      );
    }
    if (holes.length != 18 ||
        startHole != 0 ||
        holesPlayed < 10 ||
        holesPlayed > 18) {
      return null;
    }
    return whs.unroundedCourseHandicap(
      handicapIndex: handicapIndex,
      slopeRating: slope.toDouble(),
      courseRating: rating,
      par: par,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'rating': rating,
    'slope': slope,
    'frontNineRating': frontNineRating,
    'frontNineSlope': frontNineSlope,
    'backNineRating': backNineRating,
    'backNineSlope': backNineSlope,
    'holes': holes.map((h) => h.toJson()).toList(),
  };

  static Tee fromJson(Map<String, dynamic> j) => Tee(
    id: j['id'] as String,
    name: j['name'] as String,
    rating: (j['rating'] as num).toDouble(),
    slope: (j['slope'] as num).toInt(),
    frontNineRating: (j['frontNineRating'] as num?)?.toDouble(),
    frontNineSlope: (j['frontNineSlope'] as num?)?.toInt(),
    backNineRating: (j['backNineRating'] as num?)?.toDouble(),
    backNineSlope: (j['backNineSlope'] as num?)?.toInt(),
    holes: ((j['holes'] as List)
        .map((e) => HoleInfo.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList()),
  );
}

class Course {
  final String id;
  final String name;
  final String city;
  final String state;
  final List<Tee> tees;
  final bool custom;

  /// Local path of the scanned scorecard photo, if any.
  final String imagePath;

  /// Raw OCR text of the last scan, kept so a bad read can be diagnosed
  /// (and re-parsed after a parser fix) without re-photographing the card.
  final String ocrText;

  /// Raw text of every attempt, including the failures. One pass usually
  /// reads a garbled card better than another, so the discarded text is
  /// where a parser improvement becomes visible.
  final List<String> ocrAttempts;
  const Course({
    required this.id,
    required this.name,
    required this.city,
    required this.state,
    required this.tees,
    this.custom = false,
    this.imagePath = '',
    this.ocrText = '',
    this.ocrAttempts = const [],
  });

  /// This course with its scan photo repointed, for when a restored backup
  /// has the bytes on disk and the course still points nowhere.
  Course copyWithImagePath(String path) => Course(
    id: id,
    name: name,
    city: city,
    state: state,
    tees: tees,
    custom: custom,
    imagePath: path,
    ocrText: ocrText,
    ocrAttempts: ocrAttempts,
  );

  /// This course with an extra tee appended.
  ///
  /// Courses are immutable here so a restore cannot quietly repoint a course
  /// the app is already using, which is why adding a tee is a replacement
  /// rather than an in-place append.
  Course withTee(Tee tee) => Course(
    id: id,
    name: name,
    city: city,
    state: state,
    tees: [...tees, tee],
    custom: custom,
    imagePath: imagePath,
    ocrText: ocrText,
    ocrAttempts: ocrAttempts,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'city': city,
    'state': state,
    'tees': tees.map((t) => t.toJson()).toList(),
    'imagePath': imagePath,
    'ocrText': ocrText,
    'ocrAttempts': ocrAttempts,
  };

  static Course fromJson(Map<String, dynamic> j, {bool custom = true}) =>
      Course(
        id: j['id'] as String,
        name: j['name'] as String,
        city: j['city'] as String? ?? '',
        state: j['state'] as String? ?? '',
        tees: ((j['tees'] as List)
            .map((e) => Tee.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList()),
        custom: custom,
        imagePath: j['imagePath'] as String? ?? '',
        ocrText: j['ocrText'] as String? ?? '',
        ocrAttempts: ((j['ocrAttempts'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
      );

  /// The tee to preselect for a new round.
  ///
  /// White is the default where the course has one, because that is the tee
  /// most golfers actually play, and it is the name used often enough across
  /// enough courses to be a reliable signal.
  ///
  /// Failing that, the second tee. Tee data is stored longest first, so the
  /// first is the hardest, which is too much club for most golfers, and
  /// picking by position works whatever the course calls its tees — plenty of
  /// them do not use colour names at all. A course with one tee gets it.
  Tee get defaultTee {
    if (tees.isEmpty) {
      throw StateError('Course $id has no tees');
    }
    for (final t in tees) {
      if (t.name.trim().toLowerCase() == 'white') return t;
    }
    return tees.length > 1 ? tees[1] : tees.first;
  }
}

class HoleScore {
  int score;
  int putts;
  String fairway; // L, H, R, NA
  int penalties;
  int driveDistance;

  /// Green in regulation, entered by the user (default false).
  bool gir;
  HoleScore({
    required this.score,
    this.putts = 2,
    this.fairway = 'NA',
    this.penalties = 0,
    this.driveDistance = 0,
    this.gir = false,
  });

  /// An independent copy, so an editor can be abandoned without having
  /// already changed the round it was opened for.
  HoleScore copy() => HoleScore(
    score: score,
    putts: putts,
    fairway: fairway,
    penalties: penalties,
    driveDistance: driveDistance,
    gir: gir,
  );

  /// Scoring math guardrails: putts are always strokes on the green, so
  /// at least one non-putt stroke got the ball there (putts <= score - 1,
  /// 0 for a hole-in-one). Penalty strokes are part of the score, so at
  /// least one non-penalty stroke must remain (score >= penalties + 1).
  void sanitize() {
    score = score.clamp(1, 12);
    putts = putts.clamp(0, score - 1);
    penalties = penalties.clamp(0, (score - 1).clamp(0, 4));
  }

  Map<String, dynamic> toJson() => {
    'score': score,
    'putts': putts,
    'fairway': fairway,
    'penalties': penalties,
    'driveDistance': driveDistance,
    'gir': gir,
  };

  static HoleScore fromJson(Map<String, dynamic> j) => HoleScore(
    score: (j['score'] as num).toInt(),
    putts: (j['putts'] as num?)?.toInt() ?? 2,
    fairway: j['fairway'] as String? ?? 'NA',
    penalties: (j['penalties'] as num?)?.toInt() ?? 0,
    driveDistance: (j['driveDistance'] as num?)?.toInt() ?? 0,
    gir: j['gir'] as bool? ?? false,
  );
}

class Round {
  final String id;
  final String courseId;
  final String teeId;
  final DateTime playedAt;
  final String format; // stroke | match | stableford
  final bool isTournament;
  final List<HoleScore> holes; // 9, 10-18 entries
  final double pcc;
  final bool incompleteRoundReasonValid;

  /// There is no remote backend (no accounts, no API), so a posted round is
  /// complete as soon as it is saved; nothing is left pending.
  bool pendingSync;
  // Frozen handicap snapshot at tee time:
  final int? courseHandicap;
  final double? handicapIndexAtPlay;

  Round({
    required this.id,
    required this.courseId,
    required this.teeId,
    required this.playedAt,
    this.format = 'stroke',
    this.isTournament = false,
    required this.holes,
    this.pcc = 0.0,
    this.incompleteRoundReasonValid = false,
    this.pendingSync = false,
    this.courseHandicap,
    this.handicapIndexAtPlay,
    this.startHole = 0,
    this.imagePath = '',
  });

  int get totalGross => holes.fold(0, (s, h) => s + h.score);
  int get totalPutts => holes.fold(0, (s, h) => s + h.putts);
  int get totalPenalties => holes.fold(0, (s, h) => s + h.penalties);

  /// Where this round's [holes] begin in the tee's hole list: 0 for an
  /// 18-hole round or the front nine, 9 for the back nine.
  ///
  /// Without it a back-nine round is indistinguishable from a front-nine one,
  /// so its pars, yardages and stroke indexes would all be read off the wrong
  /// holes. Always 0 for 18-hole rounds.
  final int startHole;

  /// True when this round covered the back nine of an 18-hole tee.
  bool get isBackNine => holes.length == 9 && startHole >= 9;

  /// Path of this round's scorecard photo in app storage, '' when none.
  /// Mirrors [Course.imagePath], including the backup round-trip.
  final String imagePath;

  /// This round repointed at [path], for restores and photo edits.
  Round copyWithImagePath(String path) => Round(
    id: id,
    courseId: courseId,
    teeId: teeId,
    playedAt: playedAt,
    format: format,
    isTournament: isTournament,
    holes: holes,
    pcc: pcc,
    incompleteRoundReasonValid: incompleteRoundReasonValid,
    pendingSync: pendingSync,
    courseHandicap: courseHandicap,
    handicapIndexAtPlay: handicapIndexAtPlay,
    startHole: startHole,
    imagePath: path,
  );

  /// The par for each hole this round covered, from the tee it was played on.
  ///
  /// Returns null when the tee no longer covers the round's holes, so callers
  /// can tell "no par known" from "par 0".
  List<int>? parsOn(Tee tee) {
    if (startHole + holes.length > tee.holes.length) return null;
    return tee.parsFrom(startHole, holes.length);
  }

  /// Par for the holes played, or null if the tee can no longer be read.
  int? parPlayed(Tee tee) => parsOn(tee)?.fold<int>(0, (s, v) => s + v);

  double? differential(Tee tee) {
    if (holes.length == 9) {
      final differential = _nineHoleDifferential(tee);
      return differential == null ? null : (differential * 10).round() / 10.0;
    }
    if (!_hasUsableHandicapRatings(tee)) return null;
    final adj = adjustedGrossForDifferential(tee);
    if (adj == null) return null;
    return whs.scoreDifferential(
      adjustedGrossScore: adj,
      courseRating: tee.rating,
      slopeRating: tee.slope.toDouble(),
      pcc: pcc,
    );
  }

  double? unroundedDifferential(Tee tee) {
    if (holes.length == 9) return _nineHoleDifferential(tee);
    if (!_hasUsableHandicapRatings(tee)) return null;
    final adj = adjustedGrossForDifferential(tee);
    if (adj == null) return null;
    return whs.scoreDifferentialUnrounded(
      adjustedGrossScore: adj,
      courseRating: tee.rating,
      slopeRating: tee.slope.toDouble(),
      pcc: pcc,
    );
  }

  bool _hasUsableHandicapRatings(Tee tee) =>
      tee.rating.isFinite && tee.rating > 0 && tee.slope > 0;

  double? _nineHoleDifferential(Tee tee) {
    final index = handicapIndexAtPlay;
    final playedDifferential = nineHolePlayedDifferential(tee);
    if (index == null || playedDifferential == null) return null;
    return playedDifferential + whs.expectedNineHoleScoreDifferential(index);
  }

  /// The differential for only the nine played, before adding the WHS
  /// expected score for the unplayed nine.
  double? nineHolePlayedDifferential(Tee tee) {
    if (holes.length != 9 || startHole + holes.length > tee.holes.length) {
      return null;
    }
    final ratings = tee.nineHoleRatings(startHole);
    if (ratings == null) return null;
    final adjustedGross = adjustedGrossFor(tee);
    if (adjustedGross == null) return null;
    return whs.scoreDifferentialUnrounded(
      adjustedGrossScore: adjustedGross,
      courseRating: ratings.rating,
      slopeRating: ratings.slope.toDouble(),
      pcc: pcc / 2,
    );
  }

  double? adjustedGrossForDifferential(Tee tee) {
    if (tee.holes.length != 18 || startHole != 0) return null;
    if (holes.length == 9 || holes.length < 10 || holes.length > 18) {
      return null;
    }
    if (holes.length < 18 && !incompleteRoundReasonValid) return null;
    final adj = adjustedGrossFor(tee);
    if (adj == null) return null;
    if (holes.length == 18) return adj.toDouble();

    final index = handicapIndexAtPlay;
    if (index == null) return null;
    // Estimate the unplayed holes from the recorded index and whole-course
    // expected Course Handicap; unlike a net-par fill, this follows the
    // player's expected scoring level.
    final expectedStrokesPerHole =
        whs.unroundedCourseHandicap(
          handicapIndex: index,
          slopeRating: tee.slope.toDouble(),
          courseRating: tee.rating,
          par: tee.par,
        ) /
        18.0;
    final unplayedPar = tee.holes
        .skip(holes.length)
        .fold<int>(0, (sum, hole) => sum + hole.par);
    return adj + unplayedPar + expectedStrokesPerHole * (18 - holes.length);
  }

  /// The handicap-adjusted score for this round, or null if the tee it was
  /// played on no longer covers it.
  ///
  /// Split out of [differential] so an export can report the adjusted score
  /// without recomputing (or guessing at) the same handicap inputs.
  int? adjustedGrossFor(Tee tee) {
    if (tee.holes.length < startHole + holes.length) return null;
    final effectiveCourseHandicap =
        courseHandicap ??
        (handicapIndexAtPlay == null
            ? 0
            : tee.courseHandicapForRound(
                    holesPlayed: holes.length,
                    startHole: startHole,
                    handicapIndex: handicapIndexAtPlay!,
                  ) ??
                  0);
    final ratedHoles = tee.holes.skip(startHole).take(holes.length).toList();
    return whs.adjustedGross(
      scores: holes.map((h) => h.score).toList(),
      pars: tee.holes
          .skip(startHole)
          .take(holes.length)
          .map((h) => h.par)
          .toList(),
      strokeIndexes: [
        for (var i = 0; i < ratedHoles.length; i++)
          ratedHoles[i].strokeIndex ??
              _estimatedStrokeIndex(startHole + i, tee.holes.length),
      ],
      courseHandicap: effectiveCourseHandicap,
      handicapIndexExists:
          handicapIndexAtPlay != null || courseHandicap != null,
    );
  }

  int _estimatedStrokeIndex(int holeIndex, int holeCount) {
    if (holeCount <= 9) return holeIndex + 1;
    return holeIndex < 9 ? holeIndex * 2 + 1 : (holeIndex - 8) * 2;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'courseId': courseId,
    'teeId': teeId,
    'playedAt': playedAt.toIso8601String(),
    'format': format,
    'isTournament': isTournament,
    'holes': holes.map((h) => h.toJson()).toList(),
    'pcc': pcc,
    'incompleteRoundReasonValid': incompleteRoundReasonValid,
    'pendingSync': pendingSync,
    'courseHandicap': courseHandicap,
    'handicapIndexAtPlay': handicapIndexAtPlay,
    'startHole': startHole,
    'imagePath': imagePath,
  };

  static Round fromJson(Map<String, dynamic> j) => Round(
    id: j['id'] as String,
    courseId: j['courseId'] as String,
    teeId: j['teeId'] as String,
    playedAt: DateTime.parse(j['playedAt'] as String),
    format: j['format'] as String? ?? 'stroke',
    isTournament: j['isTournament'] as bool? ?? false,
    holes: ((j['holes'] as List)
        .map((e) => HoleScore.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList()),
    pcc: (j['pcc'] as num?)?.toDouble() ?? 0.0,
    incompleteRoundReasonValid:
        j['incompleteRoundReasonValid'] as bool? ?? false,
    pendingSync: j['pendingSync'] as bool? ?? false,
    courseHandicap: (j['courseHandicap'] as num?)?.toInt(),
    handicapIndexAtPlay: (j['handicapIndexAtPlay'] as num?)?.toDouble(),
    // Rounds saved before the back nine was selectable were all front
    // nine or 18 holes, which is hole 0.
    startHole: (j['startHole'] as num?)?.toInt() ?? 0,
    imagePath: j['imagePath'] as String? ?? '',
  );
}

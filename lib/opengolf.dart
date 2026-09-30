import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'scorecard_scan.dart' show validStrokeIndexes;

/// Client for OpenGolfAPI (https://opengolfapi.org), the open database of
/// US golf courses: name, GPS, scorecard pars, contact info.
///
/// License: ODbL 1.0 — any screen showing these results must carry
/// [attribution]. No API key needed; hosted API allows ~1,000 calls/day,
/// so the app fetches on demand and caches imports on-device.
const openGolfAttribution =
    'Course data © OpenStreetMap contributors via OpenGolfAPI (opengolfapi.org), ODbL 1.0';

class OpenGolfException implements Exception {
  final String message;
  const OpenGolfException(this.message);
  @override
  String toString() => message;
}

class OpenGolfCourse {
  final String id;
  final String name;
  final String city;
  final String state;
  final int? holes;
  final int? par;
  final double? lat;
  final double? lon;
  final String? type;

  const OpenGolfCourse({
    required this.id,
    required this.name,
    this.city = '',
    this.state = '',
    this.holes,
    this.par,
    this.lat,
    this.lon,
    this.type,
  });

  static OpenGolfCourse fromJson(Map<String, dynamic> j) => OpenGolfCourse(
    id: j['id'] as String? ?? '',
    name: (j['name'] ?? j['course_name'] ?? 'Unknown course') as String,
    city: (j['city'] ?? '') as String,
    state: (j['state'] ?? '') as String,
    holes: (j['holes'] as num?)?.toInt(),
    par: (j['par'] as num?)?.toInt(),
    lat: (j['latitude'] as num?)?.toDouble(),
    lon: (j['longitude'] as num?)?.toDouble(),
    type: j['type'] as String?,
  );

  String get subtitle {
    final place = [city, state].where((s) => s.isNotEmpty).join(', ');
    final bits = [if (place.isNotEmpty) place];
    if (holes != null) bits.add('$holes holes');
    if (par != null) bits.add('par $par');
    return bits.join(' • ');
  }
}

class OpenGolfHole {
  final int hole;
  final int par;
  const OpenGolfHole({required this.hole, required this.par});

  static OpenGolfHole fromJson(Map<String, dynamic> j) => OpenGolfHole(
    hole: (j['hole'] as num).toInt(),
    par: (j['par'] as num?)?.toInt() ?? 4,
  );
}

class OpenGolfDetail extends OpenGolfCourse {
  final List<OpenGolfHole> scorecard;
  final String address;
  final String phone;
  final String website;

  const OpenGolfDetail({
    required super.id,
    required super.name,
    super.city,
    super.state,
    super.holes,
    super.par,
    super.lat,
    super.lon,
    super.type,
    this.scorecard = const [],
    this.address = '',
    this.phone = '',
    this.website = '',
  });

  static OpenGolfDetail fromJson(Map<String, dynamic> j) {
    final base = OpenGolfCourse.fromJson(j);
    return OpenGolfDetail(
      id: base.id,
      name: base.name,
      city: base.city,
      state: base.state,
      holes: base.holes,
      par: base.par,
      lat: base.lat,
      lon: base.lon,
      type: base.type,
      scorecard: ((j['scorecard'] as List?) ?? [])
          .map(
            (e) => OpenGolfHole.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(),
      address: (j['address'] ?? '') as String,
      phone: (j['phone'] ?? '') as String,
      website: (j['website'] ?? '') as String,
    );
  }
}

/// One tee box as the database records it.
///
/// [gender] is 'Male' or 'Female'. The app keeps a single rating per tee
/// (men's), so female rows are dropped on import rather than merged.
class OpenGolfTee {
  final String key;
  final String name;
  final String gender;
  final double rating;
  final int slope;
  final int par;
  final int yardage;

  const OpenGolfTee({
    required this.key,
    required this.name,
    required this.gender,
    required this.rating,
    required this.slope,
    required this.par,
    required this.yardage,
  });

  bool get isMale => gender.toLowerCase().startsWith('m');

  static OpenGolfTee fromJson(Map<String, dynamic> j) => OpenGolfTee(
    key: j['tee_key'] as String? ?? '',
    name: j['tee_name'] as String? ?? 'Tee',
    gender: j['gender'] as String? ?? '',
    rating: (j['course_rating'] as num?)?.toDouble() ?? 0,
    slope: (j['slope'] as num?)?.toInt() ?? 0,
    par: (j['par'] as num?)?.toInt() ?? 72,
    yardage: (j['yardage'] as num?)?.toInt() ?? 0,
  );
}

/// One hole with its par, stroke index, and whatever yardages exist.
class OpenGolfHoleFull {
  final int number;
  final int par;
  final int handicapIndex;

  /// Per-tee yardage keyed by tee_key stem, e.g. 'black'. Zero when the
  /// database has no per-hole yardage for that tee.
  final Map<String, int> yardages;

  const OpenGolfHoleFull({
    required this.number,
    required this.par,
    required this.handicapIndex,
    this.yardages = const {},
  });

  /// Parses the '/holes' record. The stroke index is usually a 1..18
  /// permutation but is not trusted until [validStrokeIndexes] checks it.
  static OpenGolfHoleFull fromJson(Map<String, dynamic> j) {
    final raw = (j['yardages'] as Map?) ?? const {};
    final yards = <String, int>{};
    for (final e in raw.entries) {
      final v = (e.value as num?)?.toInt();
      if (v != null && v > 0) yards[e.key as String] = v;
    }
    return OpenGolfHoleFull(
      number: (j['number'] as num?)?.toInt() ?? 0,
      par: (j['par'] as num?)?.toInt() ?? 4,
      handicapIndex: (j['handicap_index'] as num?)?.toInt() ?? 0,
      yardages: yards,
    );
  }
}

class OpenGolfApi {
  static const _host = 'api.opengolfapi.org';
  final http.Client _client;

  OpenGolfApi({http.Client? client}) : _client = client ?? http.Client();

  /// Name search.
  ///
  /// The hosted API only matches short name queries (a full
  /// "name + city + state" query returns nothing), so this tries the full
  /// query first and then progressively shorter token prefixes until
  /// something matches. Results are re-ranked client-side so query tokens
  /// matching city/state (e.g. "lakeville mn") float the right course —
  /// e.g. one of several identically-named clubs — to the top.
  Future<List<OpenGolfCourse>> search(String query, {int limit = 20}) async {
    final tokens = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return [];
    List<OpenGolfCourse> found = [];
    for (var n = tokens.length; n >= 1 && found.isEmpty; n--) {
      final uri = Uri.https(_host, '/v1/courses/search', {
        'q': tokens.take(n).join(' '),
      });
      final body = await _get(uri);
      final decoded = json.decode(body);
      final list = decoded is Map && decoded['courses'] is List
          ? decoded['courses'] as List
          : decoded is List
          ? decoded
          : <dynamic>[];
      found = list
          .map(
            (e) => OpenGolfCourse.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .where((c) => c.id.isNotEmpty)
          .toList();
    }
    found.sort((a, b) => rankScore(b, tokens).compareTo(rankScore(a, tokens)));
    return found.take(limit).toList();
  }

  /// Relevance of [course] for [tokens]: name hits count double,
  /// city/state hits triple (disambiguates same-name clubs).
  static int rankScore(OpenGolfCourse course, List<String> tokens) {
    var score = 0;
    final name = course.name.toLowerCase();
    final place = '${course.city} ${course.state}'.toLowerCase();
    for (final t in tokens) {
      if (name.contains(t)) score += 2;
      if (place.contains(t)) score += 3;
    }
    return score;
  }

  /// Full record incl. hole-by-hole pars.
  Future<OpenGolfDetail> fetchCourse(String id) async {
    final uri = Uri.https(_host, '/v1/courses/$id');
    final body = await _get(uri);
    return OpenGolfDetail.fromJson(
      Map<String, dynamic>.from(json.decode(body) as Map),
    );
  }

  /// Tee boxes with rating, slope, par and total yardage.
  Future<List<OpenGolfTee>> fetchTees(String id) async {
    final uri = Uri.https(_host, '/v1/courses/$id/tees');
    final body = await _get(uri);
    final j = Map<String, dynamic>.from(json.decode(body) as Map);
    return ((j['tees'] as List?) ?? const [])
        .map((e) => OpenGolfTee.fromJson(Map<String, dynamic>.from(e as Map)))
        .where((t) => t.rating > 0 && t.slope > 0)
        .toList();
  }

  /// Holes with par, the card's stroke index, and any per-hole yardages.
  Future<List<OpenGolfHoleFull>> fetchHoles(String id) async {
    final uri = Uri.https(_host, '/v1/courses/$id/holes');
    final body = await _get(uri);
    final j = Map<String, dynamic>.from(json.decode(body) as Map);
    final holes = ((j['holes'] as List?) ?? const [])
        .map((e) => OpenGolfHoleFull.fromJson(Map<String, dynamic>.from(e as Map)))
        .where((h) => h.number >= 1)
        .toList()
      ..sort((a, b) => a.number.compareTo(b.number));
    return holes;
  }

  /// Tee boxes and holes in one call pair, for building a full course.
  ///
  /// Both requests are needed: [fetchTees] carries the rating and slope that
  /// decide a course handicap, and [fetchHoles] carries the par and stroke
  /// index. Neither alone is enough to import a usable tee.
  Future<({List<OpenGolfTee> tees, List<OpenGolfHoleFull> holes})>
  fetchScorecard(String id) async {
    final results = await Future.wait([fetchTees(id), fetchHoles(id)]);
    return (tees: results[0] as List<OpenGolfTee>, holes: results[1] as List<OpenGolfHoleFull>);
  }

  Future<String> _get(Uri uri) async {
    try {
      final res = await _client.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        throw OpenGolfException(
          'Course search failed (HTTP ${res.statusCode}). Try again later.',
        );
      }
      return res.body;
    } on OpenGolfException {
      rethrow;
    } catch (_) {
      throw const OpenGolfException(
        'No connection — online search needs internet. Your saved courses still work offline.',
      );
    }
  }
}

/// App tees built from an OpenGolfAPI tee list plus its hole data.
///
/// Returns null when nothing usable came back, so the caller can fall back to
/// the name-only draft rather than importing a tee with no rating or slope.
List<Tee>? teesFromScorecard(
  String courseId,
  List<OpenGolfTee> tees,
  List<OpenGolfHoleFull> holes,
) {
  if (tees.isEmpty || holes.isEmpty) return null;
  final count = holes.length;
  final byNumber = {for (final h in holes) h.number: h};

  // The card's own stroke index, when the database holds a clean 1..n
  // permutation. Otherwise the standard odd-front/even-back estimate.
  final dbIndexes = [
    for (var i = 1; i <= count; i++) byNumber[i]?.handicapIndex ?? 0,
  ];
  final indexes = validStrokeIndexes(dbIndexes, count)
      ? dbIndexes
      : estimateStrokeIndexes(count);

  // Mens tees only: the app stores one rating per tee, so a ladies row would
  // post a men's handicap as if it applied to everyone.
  final out = <Tee>[];
  for (final t in tees.where((t) => t.isMale)) {
    final stem = t.key.replaceAll(RegExp(r'-(male|female)$'), '');
    out.add(
      Tee(
        id: '$courseId-${_slug(t.name)}-${_slug(stem)}',
        name: t.name,
        rating: t.rating,
        slope: t.slope,
        holes: [
          for (var n = 1; n <= count; n++)
            HoleInfo(
              number: n,
              // Per-hole par comes from the hole record, not the tee's par
              // total: dividing a total by 18 loses the 3s and 5s, and tees on
              // the same course can disagree on par (71 and 72 here).
              par: _parFor(byNumber, n),
              // Per-hole yardage is only published for some tees; zero means
              // unknown, which the add-course form already renders as "—".
              yardage: byNumber[n]?.yardages[stem] ?? 0,
              strokeIndex: indexes[n - 1],
            ),
        ],
      ),
    );
  }
  return out.isEmpty ? null : out;
}

/// Per-hole par, clamped to the 3-5 a real hole can be.
int _parFor(Map<int, OpenGolfHoleFull> byNumber, int n) {
  final p = byNumber[n]?.par ?? 4;
  return p.clamp(3, 5);
}

String _slug(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-|-$'), '');

/// Pars for holes 1..[holesCount] from a detail record, matched by hole
/// number (not list position). Missing holes default to par 4.
List<int> parsForHoles(OpenGolfDetail detail, int holesCount) {
  final byHole = <int, int>{};
  for (final h in detail.scorecard) {
    byHole[h.hole] = h.par.clamp(3, 5);
  }
  return List.generate(holesCount, (i) => byHole[i + 1] ?? 4);
}

/// Estimated stroke indexes when the database has none (it never does):
/// odd numbers on the front nine, even on the back — the standard
/// fallback. Fix from the scorecard when known.
List<int> estimateStrokeIndexes(int holesCount) {
  if (holesCount <= 9) return List.generate(holesCount, (i) => i + 1);
  final front = List.generate(9, (i) => i * 2 + 1);
  final back = List.generate(holesCount - 9, (i) => (i + 1) * 2);
  return [...front, ...back];
}

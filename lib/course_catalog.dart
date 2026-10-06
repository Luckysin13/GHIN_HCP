import 'dart:convert';

import 'package:flutter/services.dart';

import 'csv_import.dart' show parseCsvTable;
import 'models.dart';
import 'opengolf.dart';

class CourseCatalogFormatException implements Exception {
  final String message;
  const CourseCatalogFormatException(this.message);
  @override
  String toString() => message;
}

class CourseCatalogCourse {
  final String state;
  final String sourceId;
  final String facilityName;
  final String name;
  final String city;

  const CourseCatalogCourse({
    required this.state,
    required this.sourceId,
    required this.facilityName,
    required this.name,
    required this.city,
  });

  String get appCourseId => 'ncrdb-${state.toLowerCase()}-$sourceId';
  String get searchText => '$name $facilityName $city $state'.toLowerCase();
}

class CourseCatalogTee {
  final String courseId;
  final String name;
  final String gender;
  final int holes;
  final int par;
  final double rating;
  final int slope;
  final double? bogeyRating;
  final double? frontNineRating;
  final int? frontNineSlope;
  final double? frontNineBogeyRating;
  final double? backNineRating;
  final int? backNineSlope;
  final double? backNineBogeyRating;

  const CourseCatalogTee({
    required this.courseId,
    required this.name,
    required this.gender,
    required this.holes,
    required this.par,
    required this.rating,
    required this.slope,
    this.bogeyRating,
    this.frontNineRating,
    this.frontNineSlope,
    this.frontNineBogeyRating,
    this.backNineRating,
    this.backNineSlope,
    this.backNineBogeyRating,
  });

  String get displayName {
    final label = switch (gender.toUpperCase()) {
      'M' => 'Men',
      'F' => 'Women',
      '' => '',
      _ => gender,
    };
    return label.isEmpty ? name : '$name ($label)';
  }
}

class CourseCatalogTeeImport {
  final List<Tee> tees;
  final int teesWithOnlinePars;
  final int teesWithYardage;
  final int totalTees;
  final Map<String, int> expectedParByTee;
  final Map<String, List<int>> missingParHolesByTee;

  const CourseCatalogTeeImport({
    required this.tees,
    required this.teesWithOnlinePars,
    required this.teesWithYardage,
    required this.totalTees,
    required this.expectedParByTee,
    required this.missingParHolesByTee,
  });

  String get onlineStatus {
    if (teesWithOnlinePars == 0 && teesWithYardage == 0) {
      return 'No matching online scorecard data was found. Tee ratings are '
          'filled from the local catalog; enter pars and yardages from the '
          'course scorecard before saving.';
    }
    return 'Online scorecard data supplied pars for $teesWithOnlinePars of '
        '$totalTees tees and complete per-hole yardages for $teesWithYardage '
        'of $totalTees tees. Review any blanks against the scorecard.';
  }
}

CourseCatalogTeeImport buildCourseCatalogTeeImport({
  required String courseId,
  required List<CourseCatalogTee> catalogTees,
  List<OpenGolfTee> onlineTees = const [],
  List<OpenGolfHoleFull> onlineHoles = const [],
}) {
  final holesByNumber = {for (final hole in onlineHoles) hole.number: hole};
  final teesWithData = <Tee>[];
  var teesWithOnlinePars = 0;
  var teesWithYardage = 0;
  final expectedParByTee = <String, int>{};
  final missingParHolesByTee = <String, List<int>>{};

  for (var teeIndex = 0; teeIndex < catalogTees.length; teeIndex++) {
    final source = catalogTees[teeIndex];
    final matchingOnlineTees = onlineTees
        .where((tee) => _sameTee(source, tee))
        .toList();
    final onlineTee = matchingOnlineTees.length == 1
        ? matchingOnlineTees.single
        : null;
    final matchingHoles =
        onlineTee != null && onlineHoles.length == source.holes
        ? onlineHoles
        : const <OpenGolfHoleFull>[];
    final stem = onlineTee?.key
        .replaceFirst(RegExp(r'-(male|female)$', caseSensitive: false), '')
        .toLowerCase();
    final yardageKey = stem?.isNotEmpty == true
        ? stem!
        : onlineTee?.color.toLowerCase();
    final missingPars = [
      for (var number = 1; number <= source.holes; number++)
        if (matchingHoles.isEmpty ||
            holesByNumber[number]?.par == null ||
            holesByNumber[number]?.hasPar != true ||
            holesByNumber[number]!.par < 3 ||
            holesByNumber[number]!.par > 5)
          number,
    ];
    final hasAllPars = missingPars.isEmpty;
    final holes = <HoleInfo>[];
    final rawIndexes = [
      for (var i = 1; i <= source.holes; i++)
        holesByNumber[i]?.handicapIndex ?? 0,
    ];
    final indexes = [
      for (final index in rawIndexes)
        if (index >= 1 && index <= source.holes) index else null,
    ];
    for (var number = 1; number <= source.holes; number++) {
      final onlineHole = matchingHoles.isEmpty ? null : holesByNumber[number];
      final par = onlineHole?.par;
      final yardage = yardageKey == null
          ? null
          : onlineHole?.yardages[yardageKey];
      holes.add(
        HoleInfo(
          number: number,
          par: par != null && par >= 3 && par <= 5 ? par : 4,
          yardage: yardage ?? 0,
          strokeIndex: indexes[number - 1],
        ),
      );
    }
    if (hasAllPars) teesWithOnlinePars++;
    if (holes.every((hole) => hole.yardage > 0)) teesWithYardage++;
    final displayName = source.displayName;
    expectedParByTee[displayName] = source.par;
    if (missingPars.isNotEmpty) {
      missingParHolesByTee[displayName] = missingPars;
    }
    teesWithData.add(
      Tee(
        id: '$courseId-${_slugCourseTee(displayName)}-$teeIndex',
        name: displayName,
        rating: source.rating,
        slope: source.slope,
        frontNineRating: source.frontNineRating,
        frontNineSlope: source.frontNineSlope,
        backNineRating: source.backNineRating,
        backNineSlope: source.backNineSlope,
        holes: holes,
      ),
    );
  }
  return CourseCatalogTeeImport(
    tees: teesWithData,
    teesWithOnlinePars: teesWithOnlinePars,
    teesWithYardage: teesWithYardage,
    totalTees: catalogTees.length,
    expectedParByTee: expectedParByTee,
    missingParHolesByTee: missingParHolesByTee,
  );
}

bool _sameTee(CourseCatalogTee catalog, OpenGolfTee online) {
  final catalogName = _normalizeCourseTee(catalog.name);
  final onlineName = _normalizeCourseTee(online.name);
  if (catalogName != onlineName) return false;
  final catalogGender = catalog.gender.toLowerCase();
  final onlineGender = online.gender.toLowerCase();
  if (catalogGender.isEmpty || onlineGender.isEmpty) {
    return true;
  }
  return catalogGender.startsWith('f') == onlineGender.startsWith('f');
}

OpenGolfCourse? matchOnlineCatalogCourse(
  CourseCatalogCourse course,
  List<OpenGolfCourse> candidates,
) {
  final courseNames = {
    _normalizeCourseTee(course.name),
    _normalizeCourseTee(course.facilityName),
  }..remove('');
  final exact = candidates.where((candidate) {
    return candidate.state.toUpperCase() == course.state.toUpperCase() &&
        courseNames.contains(_normalizeCourseTee(candidate.name));
  }).toList();
  if (exact.length == 1) return exact.single;
  if (exact.isEmpty) return null;

  final city = _normalizeCourseTee(course.city);
  if (city.isEmpty) return null;
  final cityMatches = exact
      .where((candidate) => _normalizeCourseTee(candidate.city) == city)
      .toList();
  return cityMatches.length == 1 ? cityMatches.single : null;
}

String _normalizeCourseTee(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

String _slugCourseTee(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-|-$'), '');

class CourseRatingCatalog {
  final List<CourseCatalogCourse> courses;
  final String? snapshotDate;
  final Map<String, String> _stateFiles;
  final AssetBundle _bundle;
  String? _cachedState;
  List<CourseCatalogTee> _cachedTees = const [];

  CourseRatingCatalog._({
    required this.courses,
    required this.snapshotDate,
    required Map<String, String> stateFiles,
    required AssetBundle bundle,
  }) : _stateFiles = stateFiles,
       _bundle = bundle;

  static Future<CourseRatingCatalog>? _defaultLoad;

  static Future<CourseRatingCatalog> load({AssetBundle? bundle}) {
    if (bundle != null) return _load(bundle);
    return _defaultLoad ??= _load(rootBundle);
  }

  static Future<CourseRatingCatalog> _load(AssetBundle bundle) async {
    final raw = await bundle.loadString('assets/course_catalog/index.json');
    return CourseRatingCatalog.fromIndexJson(raw, bundle: bundle);
  }

  factory CourseRatingCatalog.fromIndexJson(String raw, {AssetBundle? bundle}) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const CourseCatalogFormatException(
        'The course ratings index is not a JSON object.',
      );
    }
    final stateFilesRaw = decoded['stateFiles'];
    final coursesRaw = decoded['courses'];
    if (stateFilesRaw is! Map || coursesRaw is! List) {
      throw const CourseCatalogFormatException(
        'The course ratings index is missing its state files or courses.',
      );
    }
    final stateFiles = <String, String>{};
    for (final entry in stateFilesRaw.entries) {
      if (entry.key is String && entry.value is String) {
        stateFiles[(entry.key as String).toUpperCase()] = entry.value as String;
      }
    }
    final courses = <CourseCatalogCourse>[];
    for (final entry in coursesRaw) {
      if (entry is! List || entry.length < 5) continue;
      courses.add(
        CourseCatalogCourse(
          state: '${entry[0]}'.toUpperCase(),
          sourceId: '${entry[1]}',
          facilityName: '${entry[2]}',
          name: '${entry[3]}',
          city: '${entry[4]}',
        ),
      );
    }
    return CourseRatingCatalog._(
      courses: courses,
      snapshotDate: decoded['generatedAt'] is String
          ? decoded['generatedAt'] as String
          : null,
      stateFiles: stateFiles,
      bundle: bundle ?? rootBundle,
    );
  }

  List<CourseCatalogCourse> search(String query, {int limit = 15}) {
    final tokens = query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList();
    if (tokens.isEmpty || limit <= 0) return const [];

    final matches = <(int, CourseCatalogCourse)>[];
    final fullQuery = tokens.join(' ');
    for (final course in courses) {
      if (!tokens.every(course.searchText.contains)) continue;
      final rank = course.name.toLowerCase().startsWith(fullQuery)
          ? 0
          : course.facilityName.toLowerCase().startsWith(fullQuery)
          ? 1
          : 2;
      matches.add((rank, course));
    }
    matches.sort((a, b) {
      final rank = a.$1.compareTo(b.$1);
      if (rank != 0) return rank;
      final name = a.$2.name.toLowerCase().compareTo(b.$2.name.toLowerCase());
      if (name != 0) return name;
      return a.$2.state.compareTo(b.$2.state);
    });
    return [for (final match in matches.take(limit)) match.$2];
  }

  Future<List<CourseCatalogTee>> teesFor(CourseCatalogCourse course) async {
    final file = _stateFiles[course.state];
    if (file == null) {
      throw CourseCatalogFormatException(
        'No tee data file is available for ${course.state}.',
      );
    }
    if (_cachedState != course.state) {
      _cachedTees = await _loadState(file, course.state);
      _cachedState = course.state;
    }
    return [
      for (final tee in _cachedTees)
        if (tee.courseId == course.sourceId) tee,
    ];
  }

  Future<List<CourseCatalogTee>> _loadState(String file, String state) async {
    final path = 'assets/course_catalog/$file';
    return parseCourseCatalogTeeCsv(await _bundle.loadString(path), state);
  }
}

List<CourseCatalogTee> parseCourseCatalogTeeCsv(String text, String state) {
  final rows = parseCsvTable(text);
  if (rows.isEmpty) {
    throw const CourseCatalogFormatException(
      'The state tee data file is empty.',
    );
  }
  final header = rows.first.map((value) => value.trim().toLowerCase()).toList();
  const required = [
    'course_id',
    'state',
    'tee_name',
    'gender',
    'par',
    'course_rating',
    'slope_rating',
  ];
  final missing = required.where((column) => !header.contains(column)).toList();
  if (missing.isNotEmpty) {
    throw CourseCatalogFormatException(
      'The state tee data file is missing required columns: ${missing.join(', ')}.',
    );
  }
  final columns = {for (final name in header) name: header.indexOf(name)};
  String cell(List<String> row, String name) {
    final i = columns[name];
    return i == null || i >= row.length ? '' : row[i].trim();
  }

  final output = <CourseCatalogTee>[];
  for (final row in rows.skip(1)) {
    if (cell(row, 'state').toUpperCase() != state.toUpperCase()) continue;
    final courseId = cell(row, 'course_id');
    final name = cell(row, 'tee_name');
    final par = int.tryParse(cell(row, 'par'));
    final rating = double.tryParse(cell(row, 'course_rating'));
    final slope = int.tryParse(cell(row, 'slope_rating'));
    if (courseId.isEmpty ||
        name.isEmpty ||
        par == null ||
        rating == null ||
        slope == null ||
        par < 25 ||
        par > 90 ||
        slope < 55 ||
        slope > 155) {
      continue;
    }

    final backRating =
        _number(cell(row, 'back9_rating')) ??
        _rawRating(cell(row, 'back9_raw'));
    final backSlope =
        _integer(cell(row, 'back9_slope')) ?? _rawSlope(cell(row, 'back9_raw'));
    final isNineHole = par <= 45 && backRating == null && backSlope == null;
    if (rating < (isNineHole ? 20 : 45) || rating > (isNineHole ? 45 : 90)) {
      continue;
    }
    final frontRating =
        _number(cell(row, 'front9_rating')) ??
        _number(cell(row, 'rating_f9')) ??
        _rawRating(cell(row, 'front9_raw'));
    final frontSlope =
        _integer(cell(row, 'front9_slope')) ??
        _rawSlope(cell(row, 'front9_raw'));
    final hasFrontNine =
        frontRating != null &&
        frontSlope != null &&
        frontRating >= 20 &&
        frontRating <= 45 &&
        frontSlope >= 55 &&
        frontSlope <= 155;
    final hasBackNine =
        backRating != null &&
        backSlope != null &&
        backRating >= 20 &&
        backRating <= 45 &&
        backSlope >= 55 &&
        backSlope <= 155;
    output.add(
      CourseCatalogTee(
        courseId: courseId,
        name: name,
        gender: cell(row, 'gender'),
        holes: isNineHole ? 9 : 18,
        par: par,
        rating: rating,
        slope: slope,
        bogeyRating: _number(cell(row, 'bogey_rating')),
        frontNineRating: isNineHole || !hasFrontNine ? null : frontRating,
        frontNineSlope: isNineHole || !hasFrontNine ? null : frontSlope,
        frontNineBogeyRating: _number(cell(row, 'bogey_f9')),
        backNineRating: isNineHole || !hasBackNine ? null : backRating,
        backNineSlope: isNineHole || !hasBackNine ? null : backSlope,
        backNineBogeyRating: _number(cell(row, 'bogey_b9')),
      ),
    );
  }
  return output;
}

double? _number(String value) => value.isEmpty ? null : double.tryParse(value);

int? _integer(String value) => value.isEmpty ? null : int.tryParse(value);

double? _rawRating(String value) => _number(value.split('/').first.trim());

int? _rawSlope(String value) {
  final parts = value.split('/');
  return parts.length < 2 ? null : _integer(parts[1].trim());
}

import 'package:flutter_test/flutter_test.dart';

import 'package:ghin_golf/models.dart';
import 'package:ghin_golf/store.dart';

Course _custom({
  String id = 'custom-1',
  String name = 'Pearl Valley Golf Club',
  String city = 'Cape Town',
  String state = 'WC',
}) => Course(
  id: id,
  name: name,
  city: city,
  state: state,
  tees: [
    Tee(
      id: '$id-white',
      name: 'White',
      rating: 71.5,
      slope: 128,
      holes: List.generate(
        18,
        (i) =>
            HoleInfo(number: i + 1, par: 4, yardage: 380, strokeIndex: i + 1),
      ),
    ),
  ],
  custom: true,
);

void main() {
  test('search finds courses by name, city, or state tokens', () {
    final store = GolfStore();
    expect(store.searchCourses('crystal').length, 1);
    expect(store.searchCourses('CRYSTAL LAKE').length, 1);
    expect(store.searchCourses('crystal harper').isEmpty, true);
    expect(store.searchCourses('').length, store.courses.length);
  });

  test('added custom course is searchable and deletable', () {
    final store = GolfStore();
    store.addCourse(_custom());
    expect(store.searchCourses('pearl').length, 1);
    expect(store.searchCourses('cape town').length, 1);
    store.deleteCourse('custom-1');
    expect(store.searchCourses('pearl').isEmpty, true);
    // The bundled course survives.
    expect(store.searchCourses('').length, 1);
  });

  test('the bundled course can be deleted too', () {
    final store = GolfStore();
    expect(store.courseById('crystal-lake'), isNotNull);
    store.deleteCourse('crystal-lake');
    expect(store.searchCourses('crystal').isEmpty, true);
    expect(store.courseById('crystal-lake'), isNull);
  });

  test('custom course can be edited in place', () {
    final store = GolfStore();
    store.addCourse(_custom());
    final edited = Course(
      id: 'custom-1',
      name: 'Pearl Valley Renamed',
      city: 'Cape Town',
      state: 'WC',
      tees: const [
        Tee(id: 't1', name: 'Blue', rating: 72.5, slope: 134, holes: []),
      ],
      custom: true,
    );
    store.updateCourse(edited);
    expect(store.courseById('custom-1')?.name, 'Pearl Valley Renamed');
    expect(store.courseById('custom-1')?.tees.first.name, 'Blue');
    expect(store.searchCourses('').length, 2); // no duplicate added
    store.updateCourse(_custom(id: 'missing')); // unknown id: no-op
    expect(store.searchCourses('').length, 2);
  });

  test('scorecard photo path survives a JSON round-trip', () {
    final json = _custom().toJson();
    expect(Course.fromJson(json).imagePath, '');
    json['imagePath'] = '/docs/scorecards/custom-1.jpg';
    expect(Course.fromJson(json).imagePath, '/docs/scorecards/custom-1.jpg');
  });

  test('GIR stats come from the user flag, not a formula', () {
    final store = GolfStore();
    final holes = List.generate(
      18,
      (i) => HoleScore(score: 4, putts: 2, gir: i.isEven),
    );
    store.addRound(
      Round(
        id: 'r1',
        courseId: 'crystal-lake',
        teeId: 'crystal-lake-white',
        playedAt: DateTime(2026, 1, 1),
        holes: holes,
      ),
    );
    expect(store.statSummary()['GIR'], 50.0);
  });

  test('per-round stats ignore rounds whose course is gone', () {
    final store = GolfStore();
    // Two readable rounds, one penalty on every hole of the first.
    store.addRound(
      Round(
        id: 'r1',
        courseId: 'crystal-lake',
        teeId: 'crystal-lake-white',
        playedAt: DateTime(2026, 1, 1),
        holes: List.generate(
          18,
          (i) => HoleScore(score: 4, putts: 2, penalties: 1),
        ),
      ),
    );
    store.addRound(
      Round(
        id: 'r2',
        courseId: 'crystal-lake',
        teeId: 'crystal-lake-white',
        playedAt: DateTime(2026, 1, 8),
        holes: List.generate(18, (i) => HoleScore(score: 4, putts: 2)),
      ),
    );
    expect(store.statSummary()['Pen/Round'], closeTo(9.0, 0.001));

    // A third round on a course that no longer resolves, carrying penalties
    // of its own. Its holes are never counted, so it must not be counted as a
    // round either — dividing by all three would report 6.0.
    store.addRound(
      Round(
        id: 'r3',
        courseId: 'deleted-course',
        teeId: 'deleted-tee',
        playedAt: DateTime(2026, 1, 15),
        holes: List.generate(
          18,
          (i) => HoleScore(score: 4, putts: 2, penalties: 4),
        ),
      ),
    );
    expect(store.statSummary()['Pen/Round'], closeTo(9.0, 0.001));
    expect(store.statSummary()['Putts/Hole'], closeTo(2.0, 0.001));
  });

  test('a back-nine round is graded against the back nine pars', () {
    // FIR only counts holes of par 4 or more; par 3s are dropped because
    // they are too short for a fairway. This tee is par 3 on the front and
    // par 4 on the back, so a back-nine round counts toward FIR and a
    // front-nine round does not — which makes it a sharp test of which nine
    // the scores were read against:
    //
    //   correct (holes 10-18, par 4, counted):   9/9 hits = 100%
    //   offset ignored (holes 1-9, par 3, all dropped): nothing to count = 0%
    final store = GolfStore();
    store.addCourse(
      Course(
        id: 'mixed',
        name: 'Mixed Par',
        city: '',
        state: '',
        custom: true,
        tees: [
          Tee(
            id: 'mixed-tee',
            name: 'Championship',
            rating: 72,
            slope: 130,
            holes: [
              for (var i = 0; i < 18; i++)
                HoleInfo(
                  number: i + 1,
                  par: i < 9 ? 3 : 4, // front nine par 3, back nine par 4
                  yardage: 400,
                  strokeIndex: i + 1,
                ),
            ],
          ),
        ],
      ),
    );
    store.addRound(
      Round(
        id: 'back',
        courseId: 'mixed',
        teeId: 'mixed-tee',
        playedAt: DateTime(2026, 1, 8),
        holes: List.generate(
          9,
          (i) => HoleScore(score: 4, putts: 1, fairway: 'H'),
        ),
        startHole: 9,
      ),
    );
    expect(store.statSummary()['FIR'], closeTo(100.0, 0.001));
  });

  test('a round longer than its tee is skipped, not truncated', () {
    final store = GolfStore();
    store.addCourse(
      Course(
        id: 'short',
        name: 'Short',
        city: '',
        state: '',
        custom: true,
        tees: [
          Tee(
            id: 'short-tee',
            name: 'Nine',
            rating: 70,
            slope: 130,
            holes: List.generate(
              9,
              (i) => HoleInfo(
                number: i + 1,
                par: 4,
                yardage: 380,
                strokeIndex: i + 1,
              ),
            ),
          ),
        ],
      ),
    );
    // A back-nine round on a tee that only has a front nine: the holes played
    // cannot be located, so the round is dropped instead of being read
    // against holes it was never played on.
    store.addRound(
      Round(
        id: 'impossible',
        courseId: 'short',
        teeId: 'short-tee',
        playedAt: DateTime(2026, 1, 1),
        holes: List.generate(9, (i) => HoleScore(score: 4, putts: 2)),
        startHole: 9,
      ),
    );
    expect(store.statSummary(), isEmpty);
  });

  test('custom course survives a JSON round-trip', () {
    final c = _custom();
    final back = Course.fromJson(c.toJson());
    expect(back.id, c.id);
    expect(back.name, c.name);
    expect(back.city, c.city);
    expect(back.tees.length, 1);
    expect(back.tees.first.holes.length, 18);
    expect(back.tees.first.rating, 71.5);
    expect(back.tees.first.slope, 128);
  });
}

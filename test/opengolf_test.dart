import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ghin_golf/opengolf.dart';

const _searchJson = '''
{"courses": [
  {"id": "abc-1", "name": "Pebble Beach Golf Links", "city": "Pebble Beach",
   "state": "CA", "holes": 18, "par": 72,
   "latitude": 36.5685, "longitude": -121.949, "type": "Resort/Public"},
  {"id": "", "name": "Bad row without id"}
]}''';

const _detailJson = '''
{"id": "abc-1", "name": "Pebble Beach Golf Links", "city": "Pebble Beach",
 "state": "CA", "holes": 18, "par": 72,
 "latitude": 36.5685, "longitude": -121.949,
 "address": "1700 17 Mile Dr", "phone": "(831) 574-5609",
 "scorecard": [{"hole": 1, "par": 4}, {"hole": 2, "par": 5}, {"hole": 3, "par": 4}]}''';

void main() {
  test('search parses results and drops rows without id', () async {
    final api = OpenGolfApi(
      client: MockClient((_) async => http.Response(_searchJson, 200)),
    );
    final results = await api.search('pebble');
    expect(results.length, 1);
    expect(results.first.name, 'Pebble Beach Golf Links');
    expect(results.first.state, 'CA');
    expect(results.first.par, 72);
    expect(results.first.subtitle, contains('Pebble Beach, CA'));
  });

  test('detail parses scorecard pars', () async {
    final api = OpenGolfApi(
      client: MockClient((_) async => http.Response(_detailJson, 200)),
    );
    final d = await api.fetchCourse('abc-1');
    expect(d.scorecard.length, 3);
    expect(d.scorecard.map((h) => h.par).toList(), [4, 5, 4]);
    expect(d.address, contains('17 Mile'));
  });

  test('HTTP error becomes a friendly exception', () async {
    final api = OpenGolfApi(
      client: MockClient((_) async => http.Response('busy', 429)),
    );
    expect(() => api.search('x'), throwsA(isA<OpenGolfException>()));
  });

  test(
    'full "name city state" query falls back and ranks the local match first',
    () async {
      const ri =
          '{"id": "ri-1", "name": "Crystal Lake Golf Club", "city": "Burrillville", "state": "RI", "holes": 18, "par": 71}';
      const mn =
          '{"id": "mn-1", "name": "Crystal Lake Golf Club", "city": "Lakeville", "state": "MN", "holes": 18, "par": 71}';
      final api = OpenGolfApi(
        client: MockClient((req) async {
          final q = req.url.queryParameters['q'] ?? '';
          if (q.contains('mn')) return http.Response('{"courses": []}', 200);
          return http.Response('{"courses": [$ri, $mn]}', 200);
        }),
      );
      final results = await api.search('Crystal Lake Golf Club Lakeville MN');
      expect(results.length, 2);
      // Lakeville MN outranks the name-identical RI club.
      expect(results.first.id, 'mn-1');
      expect(
        OpenGolfApi.rankScore(results.first, [
          'crystal',
          'lake',
          'golf',
          'club',
          'lakeville',
          'mn',
        ]),
        greaterThan(
          OpenGolfApi.rankScore(results.last, [
            'crystal',
            'lake',
            'golf',
            'club',
            'lakeville',
            'mn',
          ]),
        ),
      );
    },
  );

  test('pars map by hole number, SI estimate is odd-front/even-back', () async {
    final api = OpenGolfApi(
      client: MockClient((_) async => http.Response(_detailJson, 200)),
    );
    final d = await api.fetchCourse('abc-1');
    expect(parsForHoles(d, 3), [4, 5, 4]);
    expect(estimateStrokeIndexes(18).sublist(0, 9), [
      1,
      3,
      5,
      7,
      9,
      11,
      13,
      15,
      17,
    ]);
    expect(estimateStrokeIndexes(18).sublist(9), [
      2,
      4,
      6,
      8,
      10,
      12,
      14,
      16,
      18,
    ]);
    expect(estimateStrokeIndexes(9), [1, 2, 3, 4, 5, 6, 7, 8, 9]);
  });

  group('tee import', () {
    // Shapes taken from the live Valleywood response.
    const teesJson = '{"tees": ['
        '{"tee_key": "black-male", "tee_name": "Black", "gender": "Male",'
        ' "course_rating": 70.7, "slope": 127, "par": 71, "yardage": 6425},'
        '{"tee_key": "purple-female", "tee_name": "Purple", "gender": "Female",'
        ' "course_rating": 73.7, "slope": 128, "par": 71, "yardage": 6053},'
        '{"tee_key": "purple-male", "tee_name": "Purple", "gender": "Male",'
        ' "course_rating": 68.9, "slope": 121, "par": 71, "yardage": 6053},'
        '{"tee_key": "black-bogus", "tee_name": "Broken", "gender": "Male",'
        ' "course_rating": 0, "slope": 0, "par": 71, "yardage": 0}]}';

    const holesJson = '{"holes": ['
        '{"number": 1, "par": 4, "handicap_index": 4, "yardages": {"web": 349, "black": 349}},'
        '{"number": 2, "par": 3, "handicap_index": 14, "yardages": {"web": 153, "black": 153}},'
        '{"number": 3, "par": 4, "handicap_index": 8, "yardages": {"web": 395, "black": 395}}]}';

    OpenGolfApi stub() => OpenGolfApi(
      client: MockClient((req) async {
        if (req.url.path.endsWith('/tees')) return http.Response(teesJson, 200);
        if (req.url.path.endsWith('/holes')) {
          return http.Response(holesJson, 200);
        }
        return http.Response('{}', 200);
      }),
    );

    test('tees with no rating or slope are dropped', () async {
      final tees = await stub().fetchTees('abc-1');
      // The unreadable row is gone; both genders survive here on purpose,
      // because which to keep is a teesFromScorecard decision, not a parse one.
      expect(tees.map((t) => t.name), ['Black', 'Purple', 'Purple']);
      expect(tees.every((t) => t.rating > 0 && t.slope > 0), isTrue);
    });

    test('gender is parsed, not inferred from the name', () async {
      final tees = await stub().fetchTees('abc-1');
      expect(tees.firstWhere((t) => t.name == 'Black').isMale, isTrue);
      expect(tees.firstWhere((t) => t.key == 'purple-female').isMale, isFalse);
    });

    const threeTees = [
      OpenGolfTee(
        key: 'black-male',
        name: 'Black',
        gender: 'Male',
        rating: 70.7,
        slope: 127,
        par: 71,
        yardage: 6425,
      ),
      OpenGolfTee(
        key: 'purple-female',
        name: 'Purple',
        gender: 'Female',
        rating: 73.7,
        slope: 128,
        par: 71,
        yardage: 6053,
      ),
      OpenGolfTee(
        key: 'purple-male',
        name: 'Purple',
        gender: 'Male',
        rating: 68.9,
        slope: 121,
        par: 71,
        yardage: 6053,
      ),
    ];

    const oneMaleTee = OpenGolfTee(
      key: 'black-male',
      name: 'Black',
      gender: 'Male',
      rating: 70,
      slope: 120,
      par: 70,
      yardage: 6400,
    );

    test('only mens tees are imported, with rating and slope carried over', () {
      final built = teesFromScorecard('valleywood', threeTees, [
        for (var n = 1; n <= 3; n++)
          OpenGolfHoleFull(
            number: n,
            par: 4,
            handicapIndex: n,
            yardages: {'black': 300 + n},
          ),
      ]);
      expect(built, isNotNull);
      // The ladies row is dropped, not merged, so two tees named Purple
      // cannot collide and a men's rating is not posted as a ladies one.
      expect(built!.map((t) => t.rating), [70.7, 68.9]);
      expect(built.every((t) => t.id.startsWith('valleywood-')), isTrue);
      // Ids must differ despite the shared tee name.
      expect(built[1].id, isNot(built[0].id));
    });

    test('a clean stroke index from the card is used as-is', () {
      // Valleywood's real men's row, which is a valid 1..18 permutation.
      const row = [4, 14, 8, 18, 16, 10, 12, 6, 2, 7, 17, 15, 13, 11, 9, 1, 3, 5];
      final built = teesFromScorecard('c', [oneMaleTee], [
        for (var n = 1; n <= 18; n++)
          OpenGolfHoleFull(number: n, par: 4, handicapIndex: row[n - 1]),
      ])!;
      expect(built.single.holes.map((h) => h.strokeIndex), row);
    });

    test('a partial index is rejected, not partly trusted', () {
      // 3 holes cannot hold a 1..18 row, so an 18-hole card read as 3 holes
      // must fall back rather than keep three values from the real row.
      final built = teesFromScorecard('c', [oneMaleTee], [
        for (final e in [(1, 4), (2, 14), (3, 8)])
          OpenGolfHoleFull(number: e.$1, par: 4, handicapIndex: e.$2),
      ])!;
      expect(built.single.holes.map((h) => h.strokeIndex), [1, 2, 3]);
    });

    test('a bogus stroke index falls back to odd front / even back', () {
      final built = teesFromScorecard('c', [oneMaleTee], [
        // All zeros: not a permutation, so must not be trusted.
        for (var n = 1; n <= 3; n++)
          OpenGolfHoleFull(number: n, par: 4, handicapIndex: 0),
      ])!;
      expect(built.single.holes.map((h) => h.strokeIndex), [1, 2, 3]);
    });

    test('per-hole par is kept, never averaged from the tee total', () {
      final built = teesFromScorecard('c', [
        const OpenGolfTee(
          key: 'black-male',
          name: 'Black',
          gender: 'Male',
          rating: 70,
          slope: 120,
          par: 72,
          yardage: 6400,
        ),
      ], [
        for (final e in [(1, 3), (2, 5), (3, 4)])
          OpenGolfHoleFull(number: e.$1, par: e.$2, handicapIndex: e.$1),
      ])!;
      // Averaging 72/18 would have made every hole a 4 and lost the 3 and 5.
      expect(built.single.holes.map((h) => h.par), [3, 5, 4]);
    });

    test('a tee with no per-hole yardage gets 0, not the wrong tee yardage', () {
      final built = teesFromScorecard('c', [
        const OpenGolfTee(
          key: 'purple-male',
          name: 'Purple',
          gender: 'Male',
          rating: 68.9,
          slope: 121,
          par: 71,
          yardage: 6053,
        ),
      ], [
        for (var n = 1; n <= 2; n++)
          OpenGolfHoleFull(
            number: n,
            par: 4,
            handicapIndex: n,
            yardages: {'black': 349},
          ),
      ])!;
      // The database only carries Black yardages here; borrowing them for a
      // Purple tee would put 6,425 yards of numbers on the wrong box.
      expect(built.single.holes.map((h) => h.yardage), [0, 0]);
      // The rating and slope are still there, so the handicap is still right.
      expect(built.single.slope, 121);
    });

    test('returns null when the database has no usable tees', () {
      expect(
        teesFromScorecard('c', const [], [
          OpenGolfHoleFull(number: 1, par: 4, handicapIndex: 1),
        ]),
        isNull,
      );
      expect(
        teesFromScorecard('c', [oneMaleTee], const []),
        isNull,
      );
    });

    test('returns null when every tee is a ladies row', () {
      expect(
        teesFromScorecard('c', [
          const OpenGolfTee(
            key: 'purple-female',
            name: 'Purple',
            gender: 'Female',
            rating: 73.7,
            slope: 128,
            par: 71,
            yardage: 1,
          ),
        ], [OpenGolfHoleFull(number: 1, par: 4, handicapIndex: 1)]),
        isNull,
      );
    });

    test('holes arrive sorted by number, whatever order the API used', () async {
      const unsorted = '{"holes": ['
          '{"number": 3, "par": 4, "handicap_index": 8},'
          '{"number": 1, "par": 4, "handicap_index": 4},'
          '{"number": 2, "par": 3, "handicap_index": 14}]}';
      final api = OpenGolfApi(
        client: MockClient((_) async => http.Response(unsorted, 200)),
      );
      final holes = await api.fetchHoles('c');
      expect(holes.map((h) => h.number), [1, 2, 3]);
    });

    test('fetchScorecard returns tees and holes together', () async {
      final card = await stub().fetchScorecard('abc-1');
      expect(card.tees, isNotEmpty);
      expect(card.holes, hasLength(3));
    });
  });

  test('connection failure becomes an offline exception', () async {
    final api = OpenGolfApi(
      client: MockClient((_) async => throw Exception('dns')),
    );
    try {
      await api.search('x');
      fail('expected OpenGolfException');
    } on OpenGolfException catch (e) {
      expect(e.message, contains('offline'));
    }
  });
}

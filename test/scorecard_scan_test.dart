import 'package:flutter_test/flutter_test.dart';

import 'package:ghin_golf/scorecard_scan.dart';

const _ocr18 = '''
CRYSTAL LAKE GOLF CLUB
BLUE  402 515 178 441 382 201 556 432 398  410 548 165 422 388 196 571 445 402
WHITE 380 490 160 410 360 185 520 400 375  390 515 150 400 365 180 540 415 380
PAR   4   5   3   4   4   3   5   4   4    4   5   3   4   4   3   5   4   4
HCP   7   3   17  11  9  15  1  13  5    8   2   18  12  10  4   16  14  6
Rating 71.2/130
''';

const _ocr9 = '''
MEADOWBROOK
RED 320 145 480 390 350 170 500 410 360
PAR 4 3 5 4 4 3 5 4 4
SLOPE 118 RATING 68.4
''';

/// Real OCR output from a Crystal Lake photo (ground truth kept alongside
/// the app). Five tee boxes, one row each, every row ending in its own
/// rating, plus a men's and a women's handicap row. Exercises the short
/// par 3s (95, 94 yards), the OUT/IN/TOT subtotals, the hole-number header
/// and a non-color tee name all at once.
const _ocrCrystalLake = '''
CRYSTAL LAKE GOLF CLUB

1 2 3 4 5 6 7 8 9 OUT  10 11 12 13 14 15 16 17 18 IN TOT HCP NET
BLACK TEES 366 374 200 516 145 364 380 379 376 3100 490 180 397 396 355 419 334 127 525 3223 6323 70.4 -
COMBO TEES 341 374 168 489 145 364 347 341 376 2945 490 147 369 396 355 389 334 127 525 3132 6077 69.4 -
WHITE TEES 341 347 168 489 137 335 347 341 366 2871 464 147 369 373 329 389 304 109 492 2976 5847 68.3 -
YELLOW TEES 321 329 129 472 119 316 326 322 348 2682 448 133 323 352 304 364 291 95 480 2790 5472 66.5 -
MEN'S HANDICAP 12 10 16 2 18 14 8 6 4 - 11 15 3 13 9 1 5 17 7 - - - -
PAR 4 4 3 5 3 4 4 4 4 35 5 3 4 4 4 4 4 3 5 36 71 - -
RED TEES 286 264 111 407 107 284 299 291 309 2358 382 110 286 311 269 329 256 94 410 2447 4805 63.6 -
WOMEN’S HANDICAP 8 10 16 2 18 4 12 6 14 - 5 9 15 13 11 1 3 17 7 - - - -
Scorer:  Attest: Date:
''';

/// Front-nine subtotal, back-nine subtotal and total yardage as printed on
/// the card, used to prove the parsed rows are hole-accurate.
const _crystalLakeTotals = {
  'Black': [3100, 3223, 6323],
  'Combo': [2945, 3132, 6077],
  'White': [2871, 2976, 5847],
  'Yellow': [2682, 2790, 5472],
  'Red': [2358, 2447, 4805],
};

void main() {
  test('18-hole card: pars, two tees, rating/slope', () {
    final s = parseScorecardText(_ocr18);
    expect(s.pars.length, 18);
    expect(s.pars.sublist(0, 9), [4, 5, 3, 4, 4, 3, 5, 4, 4]);
    expect(s.tees.length, 2);
    expect(s.tees[0].name, 'Blue');
    expect(s.tees[0].yards.length, 18);
    expect(s.tees[0].yards.first, 402);
    expect(s.tees[1].name, 'White');
    expect(s.rating, 71.2);
    expect(s.slope, 130);
  });

  test('9-hole card with keyword rating/slope', () {
    final s = parseScorecardText(_ocr9);
    expect(s.pars.length, 9);
    expect(s.pars, [4, 3, 5, 4, 4, 3, 5, 4, 4]);
    expect(s.tees.length, 1);
    expect(s.tees.first.name, 'Red');
    expect(s.tees.first.yards.first, 320);
    expect(s.rating, 68.4);
    expect(s.slope, 118);
  });

  test('split front/back tee rows merge into whole tee boxes', () {
    const ocr = '''
BLUE 402 515 178 441 382 201 556 432 398
410 548 165 422 388 196 571 445 402
WHITE 380 490 160 410 360 185 520 400 375
390 515 150 400 365 180 540 415 380
PAR 4 5 3 4 4 3 5 4 4 4 5 3 4 4 3 5 4 4
''';
    final s = parseScorecardText(ocr);
    expect(s.tees.length, 2);
    expect(s.tees[0].name, 'Blue');
    expect(s.tees[0].yards.length, 18);
    expect(s.tees[1].name, 'White');
    expect(s.tees[1].yards.length, 18);
    expect(s.pars.length, 18);
  });

  test('split PAR lines join and HCP row is ignored', () {
    const ocr = '''
PAR 4 5 3 4 4 3 5 4 4
4 5 3 4 4 3 5 4 4
HCP 7 3 17 11 9 15 1 13 5
''';
    final s = parseScorecardText(ocr);
    expect(s.pars.length, 18);
    expect(s.pars.sublist(9), [4, 5, 3, 4, 4, 3, 5, 4, 4]);
  });

  test('rows merged onto one line split into separate tees', () {
    final nums36 = List.generate(36, (i) => 300 + (i % 18) * 5).join(' ');
    final s = parseScorecardText('BLUE $nums36\nPAR 4 4 4 4 4 4 4 4 4');
    expect(s.tees.length, 2);
    expect(s.tees[0].name, 'Blue');
    expect(s.tees[0].yards.length, 18);
    expect(s.tees[1].yards.length, 18);
    expect(s.pars.length, 9);
  });

  test('column-wise OCR transposes hole lines into all tees', () {
    final buf = StringBuffer();
    for (var h = 1; h <= 18; h++) {
      buf.writeln('$h ${400 + h} ${380 + h} ${350 + h} ${320 + h} ${300 + h}');
    }
    buf.writeln('PAR 4 4 4 4 4 4 4 4 4 4 4 4 4 4 4 4 4 4');
    final s = parseScorecardText(buf.toString());
    expect(s.tees.length, 5);
    expect(s.tees[0].yards.length, 18);
    expect(s.tees[0].yards.first, 401);
    expect(s.tees[4].yards.first, 301);
    expect(s.pars.length, 18);
  });

  test('par-first lines are not mistaken for column data', () {
    final s = parseScorecardText('4 402 380\n5 510 490\n3 170 150');
    expect(s.tees.isEmpty, true);
  });

  test('garbage text yields an empty scan without throwing', () {
    final s = parseScorecardText('hello\nworld 12\npar xyz');
    expect(s.isEmpty, true);
  });

  test('implausible rating/slope pairs are rejected', () {
    final s = parseScorecardText('PAR 4 4 4 4 4 4 4 4 4\n99.9/999');
    expect(s.pars.length, 9);
    expect(s.rating, isNull);
    expect(s.slope, isNull);
  });

  test('standalone color labels carry onto the next yardage rows', () {
    const ocr = '''
BLUE
402 515 178 441 382 201 556 432 398
410 548 165 422 388 196 571 445 402
WHITE
380 490 160 410 360 185 520 400 375
390 515 150 400 365 180 540 415 380
PAR 4 5 3 4 4 3 5 4 4 4 5 3 4 4 3 5 4 4
''';
    final s = parseScorecardText(ocr);
    expect(s.tees.length, 2);
    expect(s.tees[0].name, 'Blue');
    expect(s.tees[0].yards.length, 18);
    expect(s.tees[0].yards.first, 402);
    expect(s.tees[1].name, 'White');
    expect(s.tees[1].yards.length, 18);
  });

  test('labeled short fragments accumulate into whole tee rows', () {
    const ocr = '''
BLUE 402 515 178 441 382 201
BLUE 556 432 398 410 548 165
BLUE 422 388 196 571 445 402
WHITE 380 490 160 410 360 185
WHITE 520 400 375 390 515 150
WHITE 400 365 180 540 415 380
PAR 4 5 3 4 4 3 5 4 4 4 5 3 4 4 3 5 4 4
''';
    final s = parseScorecardText(ocr);
    expect(s.tees.length, 2);
    expect(s.tees[0].name, 'Blue');
    expect(s.tees[0].yards.length, 18);
    expect(s.tees[0].yards.first, 402);
    expect(s.tees[0].yards.last, 402);
    expect(s.tees[1].name, 'White');
    expect(s.tees[1].yards.length, 18);
  });

  test('bare rating with no slope is captured (Crystal Lake layout)', () {
    // Ground truth: /home/jonathan/CrystalLakeGolfClub.txt, BLACK row.
    const ocr = '''
CRYSTAL LAKE GOLF CLUB
BLACK TEES 366 374 200 516 145 364 380 379 376 3100 490 180 397 396 355 419 334 127 525 3223 6323 70.4 -
PAR 4 4 3 5 3 4 4 4 4 35 5 3 4 4 4 4 4 3 5 36 71 - -
''';
    final s = parseScorecardText(ocr);
    expect(s.tees.length, 1);
    expect(s.tees[0].name, 'Black');
    expect(s.tees[0].yards.length, 18);
    expect(s.tees[0].yards.first, 366);
    expect(s.pars.length, 18);
    expect(s.rating, 70.4);
    expect(s.slope, isNull);
    expect(scanGoodEnough(s), isFalse);
  });

  test('par row is found even when OCR drops the PAR label', () {
    const ocr = '''
CRYSTAL LAKE
BLUE 402 515 178 441 382 201 556 432 398 410 548 165 422 388 196 571 445 402
4 5 3 4 4 3 5 4 4
4 5 3 4 4 3 5 4 4
12 10 16 2 18 14 8 6 4 11 15 3 13 9 1 5 17 7
''';
    final s = parseScorecardText(ocr);
    expect(s.pars.length, 18);
    expect(s.pars.sublist(0, 9), [4, 5, 3, 4, 4, 3, 5, 4, 4]);
    expect(s.tees.length, 1);
    expect(s.tees[0].yards.length, 18);
  });

  test('scanQuality ranks fuller parses higher', () {
    final full = parseScorecardText(_ocr18);
    final partial = parseScorecardText(_ocr9);
    expect(scanQuality(full), greaterThan(scanQuality(partial)));
    expect(scanGoodEnough(full), isTrue);
    expect(scanGoodEnough(partial), isFalse);
    expect(scanQuality(const ScorecardScan()), 0);
  });

  test('severely garbled OCR yields no fabricated tees', () {
    // Real inspector output from a Crystal Lake photo: digits dropped,
    // split and glued. The parser must stay silent, not invent yardages
    // (ground truth: same file as above; e.g. BLACK opens 366 374 200).
    const ocr = '''
app:123 4 5 6 7 8 9   10 11 12 13 14
O BLACK TEES      5 06     56                      45 364 380                         7          180 397 396 355         5A aD fe D 5m 225)
7) COMBO TEES __ 6-10 46
JWHITE TEES 1-24 7-10
YELLOW TEES _%+ 1b
MEN'S HANDICAP
ORED TEES           :        1s 286 26:                  7 107                                                            382                 4               59 32          _                                             Ssaitl4
WOMEN'S HANDICAP                                                                       D                                        5
Scorer:                                                                                                                                             Attest:
''';
    final s = parseScorecardText(ocr);
    expect(s.tees.isEmpty, isTrue);
    expect(s.pars.isEmpty, isTrue);
    expect(scanQuality(s), 0);
  });

  test('single-number rating lines do not corrupt labeled tees', () {
    const ocr = '''
BLUE 71.2/133
BLUE 402 515 178 441 382 201 556 432 398
410 548 165 422 388 196 571 445 402
PAR 4 5 3 4 4 3 5 4 4 4 5 3 4 4 3 5 4 4
''';
    final s = parseScorecardText(ocr);
    expect(s.tees.length, 1);
    expect(s.tees[0].name, 'Blue');
    expect(s.tees[0].yards.length, 18);
    expect(s.tees[0].yards.first, 402);
    expect(s.rating, 71.2);
    expect(s.slope, 133);
    // The rating/slope line feeds the tee box it labels.
    expect(s.tees[0].rating, 71.2);
    expect(s.tees[0].slope, 133);
  });

  // ---- all tee boxes, distances, par and handicap on a real card ----

  test('real card: every tee box, all 18 distances, par and handicap', () {
    final s = parseScorecardText(_ocrCrystalLake);
    expect(s.tees.map((t) => t.name).toList(), [
      'Black',
      'Combo',
      'White',
      'Yellow',
      'Red',
    ]);
    for (final t in s.tees) {
      expect(t.yards.length, 18, reason: '${t.name} must have all 18 holes');
    }
    expect(s.tees[0].yards, [
      366,
      374,
      200,
      516,
      145,
      364,
      380,
      379,
      376,
      490,
      180,
      397,
      396,
      355,
      419,
      334,
      127,
      525,
    ]);
    // Sub-100 yard par 3s (95, 94) are real and must survive.
    expect(s.tees[3].yards[16], 95);
    expect(s.tees[4].yards[16], 94);
  });

  test('real card: parsed distances match the printed subtotals', () {
    final s = parseScorecardText(_ocrCrystalLake);
    for (final t in s.tees) {
      final want = _crystalLakeTotals[t.name]!;
      final front = t.yards.take(9).fold(0, (a, b) => a + b);
      final back = t.yards.skip(9).fold(0, (a, b) => a + b);
      expect(front, want[0], reason: '${t.name} OUT');
      expect(back, want[1], reason: '${t.name} IN');
      expect(front + back, want[2], reason: '${t.name} TOT');
    }
    // Par total matches the 71 printed on the card.
    expect(s.pars.length, 18);
    expect(s.pars.fold(0, (a, b) => a + b), 71);
    expect(s.pars.sublist(0, 9), [4, 4, 3, 5, 3, 4, 4, 4, 4]);
  });

  test('real card: each tee box keeps its own rating', () {
    final s = parseScorecardText(_ocrCrystalLake);
    expect(s.tees.map((t) => t.rating).toList(), [
      70.4,
      69.4,
      68.3,
      66.5,
      63.6,
    ]);
    expect(s.rating, 70.4);
  });

  test('real card: men handicap row is the stroke index', () {
    final s = parseScorecardText(_ocrCrystalLake);
    expect(s.hcp, [
      12,
      10,
      16,
      2,
      18,
      14,
      8,
      6,
      4,
      11,
      15,
      3,
      13,
      9,
      1,
      5,
      17,
      7,
    ]);
    expect(validStrokeIndexes(s.hcp, 18), isTrue);
  });

  test('real card parses well enough to stop retrying', () {
    final s = parseScorecardText(_ocrCrystalLake);
    expect(scanGoodEnough(s), isTrue);
    expect(s.isEmpty, isFalse);
  });

  test('tee names outside the color list are kept', () {
    const ocr = '''
COMBO TEES 341 374 168 489 145 364 347 341 376
CHAMPIONSHIP TEES 366 374 200 516 145 364 380 379 376
BACK TEES 320 329 129 472 119 316 326 322 348
PAR 4 5 3 4 4 3 5 4 4 4 5 3 4 4 3 5 4 4
''';
    final s = parseScorecardText(ocr);
    expect(s.tees.map((t) => t.name).toList(), [
      'Combo',
      'Championship',
      'Back',
    ]);
    expect(s.tees[0].yards.length, 9);
    expect(s.tees[1].yards.first, 366);
    expect(s.tees[2].yards.first, 320);
  });

  test('prose containing "tee" does not become a tee box', () {
    const ocr = '''
SEE BACK FOR TEE TIMES
BLUE 402 515 178 441 382 201 556 432 398 410 548 165 422 388 196 571 445 402
PAR 4 5 3 4 4 3 5 4 4 4 5 3 4 4 3 5 4 4
''';
    final s = parseScorecardText(ocr);
    expect(s.tees.length, 1);
    expect(s.tees[0].name, 'Blue');
  });

  test('a rating/slope pair in front of the yardages is set aside', () {
    const ocr = '''
BLUE 71.2 133 402 515 178 441 382 201 556 432 398 410 548 165 422 388 196 571 445 402
PAR 4 5 3 4 4 3 5 4 4 4 5 3 4 4 3 5 4 4
''';
    final s = parseScorecardText(ocr);
    expect(s.tees.length, 1);
    expect(s.tees[0].yards.length, 18);
    expect(s.tees[0].yards.first, 402);
    expect(s.tees[0].yards.last, 402);
    expect(s.tees[0].rating, 71.2);
    expect(s.tees[0].slope, 133);
  });

  test('a rating printed before the yardages does not shift the row', () {
    const ocr = '''
BLUE 71.2 402 515 178 441 382 201 556 432 398
410 548 165 422 388 196 571 445 402 133
PAR 4 5 3 4 4 3 5 4 4 4 5 3 4 4 3 5 4 4
''';
    final s = parseScorecardText(ocr);
    expect(s.tees.length, 1);
    expect(s.tees[0].yards.length, 18);
    expect(s.tees[0].yards.first, 402);
    expect(s.tees[0].yards.last, 402);
    expect(s.tees[0].rating, 71.2);
  });

  test(
    'a nine-hole handicap row stays nine, and a 9-row on an 18 card is dropped',
    () {
      const nine = '''
RED 320 145 480 390 350 170 500 410 360
PAR 4 3 5 4 4 3 5 4 4
HANDICAP 8 4 2 9 7 1 6 3 5
''';
      final s = parseScorecardText(nine);
      expect(s.hcp, [8, 4, 2, 9, 7, 1, 6, 3, 5]);
      expect(validStrokeIndexes(s.hcp, 9), isTrue);
      expect(validStrokeIndexes(s.hcp, 18), isFalse);

      // Half a stroke index cannot drive an 18-hole round, so it is ignored.
      final half = parseScorecardText('''
PAR 4 4 4 4 4 4 4 4 4 4 4 4 4 4 4 4 4 4
HCP 7 3 17 11 9 15 1 13 5
''');
      expect(half.hcp, isEmpty);
    },
  );

  test('a split handicap row joins front and back nine', () {
    const ocr = '''
PAR 4 5 3 4 4 3 5 4 4 4 5 3 4 4 3 5 4 4
HCP 12 10 16 2 18 14 8 6 4
11 15 3 13 9 1 5 17 7
''';
    final s = parseScorecardText(ocr);
    expect(s.hcp, [
      12,
      10,
      16,
      2,
      18,
      14,
      8,
      6,
      4,
      11,
      15,
      3,
      13,
      9,
      1,
      5,
      17,
      7,
    ]);
    expect(validStrokeIndexes(s.hcp, 18), isTrue);
  });

  test('the hole-number header is never read as a handicap', () {
    // "1 2 3 ... 18" is a permutation just like a stroke index row, and the
    // header repeats the back nine, so only a labelled/near-par row counts.
    const ocr = '''
1 2 3 4 5 6 7 8 9 OUT  10 11 12 13 14 15 16 17 18 IN TOT HCP NET
BLUE 402 515 178 441 382 201 556 432 398 410 548 165 422 388 196 571 445 402
PAR 4 5 3 4 4 3 5 4 4 4 5 3 4 4 3 5 4 4
''';
    final s = parseScorecardText(ocr);
    expect(s.hcp, isEmpty);
    expect(s.tees.length, 1);
    expect(s.tees[0].yards.length, 18);
  });

  test('a duplicated or out-of-range handicap row is rejected', () {
    // 3 appears twice and 14 is missing: not a stroke index.
    const ocr = '''
PAR 4 4 4 4 4 4 4 4 4 4 4 4 4 4 4 4 4 4
HCP 3 3 17 11 9 15 1 13 5 8 2 18 12 10 16 4 5 7
''';
    expect(parseScorecardText(ocr).hcp, isEmpty);
  });

  test('a par row whose total is impossible is not used', () {
    // Eighteen fives: a shape that fits but no course plays par 90.
    const ocr = '''
PAR 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5
BLUE 402 515 178 441 382 201 556 432 398 410 548 165 422 388 196 571 445 402
''';
    final s = parseScorecardText(ocr);
    expect(s.pars, isEmpty);
    expect(s.tees.length, 1);
  });

  test('decimal ratings are never mistaken for yardages', () {
    // 70.4 and 63.6 sit inside the yardage window as bare integers; only
    // decimal-aware tokenizing keeps them out of a tee row.
    const ocr = '''
BLUE 366 374 200 516 145 364 380 379 376 70.4
RED 286 264 111 407 107 284 299 291 309 63.6
PAR 4 4 3 5 3 4 4 4 4 4 5 3 4 4 4 4 4 3 5
''';
    final s = parseScorecardText(ocr);
    expect(s.tees.length, 2);
    expect(s.tees[0].yards.length, 9);
    expect(s.tees[0].yards.last, 376);
    expect(s.tees[1].yards.last, 309);
    expect(s.tees[0].rating, 70.4);
    expect(s.tees[1].rating, 63.6);
  });

  test('column-wise reads take tee names from a matching color legend', () {
    final buf = StringBuffer()..writeln('BLACK BLUE WHITE');
    for (var h = 1; h <= 18; h++) {
      buf.writeln('$h ${400 + h} ${380 + h} ${350 + h}');
    }
    buf.writeln('PAR 4 4 4 4 4 4 4 4 4 4 4 4 4 4 4 4 4 4');
    final s = parseScorecardText(buf.toString());
    expect(s.tees.map((t) => t.name).toList(), ['Black', 'Blue', 'White']);
    expect(s.tees[0].yards.first, 401);
    expect(s.tees[2].yards.first, 351);
  });

  test('a legend that does not match the column count is ignored', () {
    final buf = StringBuffer()..writeln('BLACK BLUE');
    for (var h = 1; h <= 18; h++) {
      buf.writeln('$h ${400 + h} ${380 + h} ${350 + h}');
    }
    final s = parseScorecardText(buf.toString());
    expect(s.tees.map((t) => t.name).toList(), ['Tee 1', 'Tee 2', 'Tee 3']);
  });

  test('validStrokeIndexes rejects estimates, gaps and duplicates', () {
    expect(validStrokeIndexes(const [1, 2, 3], 3), isTrue);
    expect(validStrokeIndexes(const [1, 2, 4], 3), isFalse);
    expect(validStrokeIndexes(const [1, 1, 2], 3), isFalse);
    expect(validStrokeIndexes(const [1, 2, 3], 18), isFalse);
    expect(validStrokeIndexes(const [], 9), isFalse);
  });
}

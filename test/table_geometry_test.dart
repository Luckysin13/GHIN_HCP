// Building hOCR the way Tesseract does, so the geometry tests read like a real
// card rather than like a tidy fixture. Boxes are laid out on a grid, which is
// what makes a lost digit *shift* values in the text read and is exactly the
// situation the column pass exists to survive.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghin_golf/hocr.dart';
import 'package:ghin_golf/scorecard_scan.dart';
import 'package:ghin_golf/table_geometry.dart';

/// Column pitch, in pixels. Wide enough that a 4-digit value still fits.
const _pitch = 110;

/// Left margin of the table.
const _left = 100;

double _x(int col) => (_left + col * _pitch).toDouble();

class _Card {
  final lines = <HocrLine>[];

  /// A text row of the card, one string per column. `null` leaves the column
  /// empty, which is how a lost value looks to OCR.
  void row(int y, List<String?> cells, {int startCol = 0}) {
    final words = <HocrWord>[];
    for (var i = 0; i < cells.length; i++) {
      final text = cells[i];
      if (text == null || text.isEmpty) continue;
      words.add(
        HocrWord(
          text: text,
          left: (_x(i + startCol) - text.length * 9).round(),
          top: y,
          right: _x(i + startCol).round(),
          bottom: y + 30,
          confidence: 92,
        ),
      );
    }
    lines.add(HocrLine(words));
  }

  /// A tee row on the grid, with [dropColumn]'s value left out.
  void teeRow(
    int y,
    List<int> yards, {
    int? frontSubtotal,
    int? backSubtotal,
    int? total,
    double? rating,
    int? dropColumn,
    Map<int, String> extra = const {},
  }) {
    final cells = List<String?>.filled(24, null);
    for (var i = 0; i < yards.length && i < 18; i++) {
      final slot = i < 9 ? i : i + 1;
      if (slot == dropColumn) continue;
      cells[slot] = '${yards[i]}';
    }
    if (frontSubtotal != null) cells[_outCol] = '$frontSubtotal';
    if (backSubtotal != null) cells[_inCol] = '$backSubtotal';
    if (total != null) cells[_totCol] = '$total';
    if (rating != null) cells[_totCol + 1] = '$rating';
    extra.forEach((slot, text) => cells[slot] = text);
    row(y, cells);
  }

  /// A word in the left margin, left of the table, as a card prints its
  /// tee name.
  void margin(int y, String text) {
    lines.add(
      HocrLine([
        HocrWord(
          text: text,
          left: 8,
          top: y,
          right: _x(0).round() - 20,
          bottom: y + 30,
          confidence: 92,
        ),
      ]),
    );
  }

  /// The same rows, rendered as hOCR markup, for the parser's own test.
  String toHocr() {
    final out = StringBuffer(
      "<div class='ocr_page' id='page_1' title='bbox 0 0 2400 1600'>\n",
    );
    for (final line in lines) {
      out.writeln("<span class='ocr_line'>");
      for (final w in line.ordered) {
        out.writeln(
          "<span class='ocrx_word' title='bbox ${w.left} ${w.top} "
          "${w.right} ${w.bottom}; x_wconf ${w.confidence}'>${w.text}</span>",
        );
      }
      out.writeln('</span>');
    }
    out.writeln('</div>');
    return out.toString();
  }
}

/// Grid slots, matching the header row exactly. The header puts OUT between
/// holes 9 and 10 and IN/TOT after hole 18, and a card prints the row's
/// subtotals under those same headings, so the row occupies the same slots.
const _outCol = 9;
const _inCol = 19;
const _totCol = 20;

/// A tee row, placed slot by slot to line up with [headerRow].
void _teeRow(
  _Card c,
  int y,
  String label,
  List<int> yards, {
  int? frontSubtotal,
  int? backSubtotal,
  int? total,
  double? rating,
  Map<int, String> extra = const {},
}) {
  c.margin(y, label);
  c.teeRow(
    y,
    yards,
    frontSubtotal: frontSubtotal,
    backSubtotal: backSubtotal,
    total: total,
    rating: rating,
    extra: extra,
  );
}

/// A tee row with a hole's value missing from its own column, which is what a
/// lost digit looks like: the column is empty, and every value after it is
/// still printed in the right place. A text read cannot tell this from a row
/// that simply ends early.
void _teeRowWithHoleDropped(
  _Card c,
  int y,
  String label,
  List<int> yards,
  int drop,
) {
  c.margin(y, label);
  c.teeRow(y, yards, dropColumn: drop);
}

/// A header with the hole numbers, OUT/IN/TOT, and the trailing columns.
_Card _cardWithHeader() {
  final c = _Card();
  final cells = List<String?>.filled(24, null);
  for (var i = 1; i <= 9; i++) {
    cells[i - 1] = '$i';
  }
  cells[_outCol] = 'OUT';
  for (var i = 10; i <= 18; i++) {
    cells[i] = '$i';
  }
  cells[_inCol] = 'IN';
  cells[_totCol] = 'TOT';
  cells[_totCol + 1] = 'HCP';
  cells[_totCol + 2] = 'NET';
  c.row(60, cells);
  return c;
}

const _black = [
  366, 374, 200, 516, 145, 364, 380, 379, 376, //
  490, 180, 397, 396, 355, 419, 334, 127, 525,
];
const _pars = [4, 4, 3, 5, 3, 4, 4, 4, 4, 5, 3, 4, 4, 4, 4, 4, 3, 5];
const _red = [
  286, 264, 111, 407, 107, 284, 299, 291, 309, //
  382, 110, 286, 311, 269, 329, 256, 94, 410,
];

void main() {
  group('hOCR parsing', () {
    test('reads the box and the text of every word', () {
      final words = parseHocrWords(_cardWithHeader().toHocr());
      // 1-9, OUT, 10-18, IN, TOT, HCP, NET
      expect(words.length, 23);
      expect(words.first.text, '1');
      expect(words.first.left, lessThan(words.first.right));
      expect(words.every((w) => w.confidence == 92), isTrue);
    });

    test('a row is not swallowed whole by its line span', () {
      // The line span carries a bbox too. Matching spans loosely would take
      // the first one and run to the first closing tag, turning a whole row
      // of yardages into a single "word" and losing every box but one.
      final words = parseHocrWords(_cardWithHeader().toHocr());
      expect(words.every((w) => !w.text.contains(' ')), isTrue);
      expect(words.map((w) => w.text), containsAll(['1', '18', 'OUT', 'NET']));
    });

    test('survives spans that carry no geometry', () {
      const hocr =
          "<span class='ocr_line'>no box here</span>"
          "<span class='ocrx_word' title='bbox 10 20 40 50; x_wconf 80'>7</span>";
      final words = parseHocrWords(hocr);
      expect(words.length, 1);
      expect(words.single.text, '7');
    });

    test('unescapes entities in a word', () {
      const hocr =
          "<span class='ocrx_word' title='bbox 1 2 3 4'>R&amp;D</span>";
      expect(parseHocrWords(hocr).single.text, 'R&D');
    });

    test('groups words into the rows they were printed on', () {
      final lines = groupHocrLines(parseHocrWords(_cardWithHeader().toHocr()));
      expect(lines.length, 1);
      expect(lines.single.ordered.map((w) => w.text).take(3), ['1', '2', '3']);
    });

    test('keeps rows apart when they are a row height apart', () {
      final c = _cardWithHeader();
      _teeRow(
        c,
        200,
        'BLACK TEES',
        _black,
        frontSubtotal: 3100,
        backSubtotal: 3223,
        total: 6323,
      );
      final lines = groupHocrLines(parseHocrWords(c.toHocr()));
      expect(lines.length, 2);
      expect(lines.last.text, startsWith('BLACK TEES 366'));
    });

    test('a number is a plain run of digits and nothing else', () {
      const w = HocrWord(
        text: '3100',
        left: 0,
        top: 0,
        right: 1,
        bottom: 1,
        confidence: 0,
      );
      expect(w.number, 3100);
      // A rating, a decimal, and anything with a sign or comma is not a
      // yardage, and treating those as one is how a slope ends up in hole 1.
      for (final t in ['70.4', '-1', '1,300', '', 'abc']) {
        expect(
          HocrWord(
            text: t,
            left: 0,
            top: 0,
            right: 1,
            bottom: 1,
            confidence: 0,
          ).number,
          isNull,
          reason: t,
        );
      }
    });
  });

  group('finding the table', () {
    test('takes the columns from the hole-number header', () {
      final columns = findTableColumns(
        groupHocrLines(parseHocrWords(_cardWithHeader().toHocr())),
      )!;
      expect(columns.holes, 18);
      // Centers land on the header's own positions.
      // Hole 1 is the first header cell; hole 18 sits after the OUT column.
      expect(columns.centers.first, closeTo(_x(0), 40));
      expect(columns.centers.last, closeTo(_x(18), 40));
    });

    test('refuses a row of numbers that is not a header', () {
      // A yardage row is 18 numbers too, but they do not count 1..18.
      final c = _Card();
      _teeRow(c, 60, 'BLACK TEES', _black);
      expect(
        findTableColumns(groupHocrLines(parseHocrWords(c.toHocr()))),
        isNull,
      );
    });

    test('refuses a header that is not evenly spaced', () {
      // Anchors this far apart are not columns, and matching to them would
      // scatter values across the wrong holes.
      final c = _Card();
      c.row(60, ['1', '2', '3', '4', '5', '6', '7', '8', '9']);
      c.lines.first.words.add(
        HocrWord(
          text: '10',
          left: 4000,
          top: 60,
          right: 4100,
          bottom: 90,
          confidence: 90,
        ),
      );
      c.lines.first.words.add(
        HocrWord(
          text: '11',
          left: 6000,
          top: 60,
          right: 6100,
          bottom: 90,
          confidence: 90,
        ),
      );
      c.lines.first.words.add(
        HocrWord(
          text: '12',
          left: 8000,
          top: 60,
          right: 8100,
          bottom: 90,
          confidence: 90,
        ),
      );
      c.lines.first.words.add(
        HocrWord(
          text: '13',
          left: 10000,
          top: 60,
          right: 10100,
          bottom: 90,
          confidence: 90,
        ),
      );
      expect(
        findTableColumns(groupHocrLines(parseHocrWords(c.toHocr()))),
        isNull,
      );
    });

    test('accepts a front-nine-only header', () {
      final c = _Card();
      c.row(60, ['1', '2', '3', '4', '5', '6', '7', '8', '9', 'OUT']);
      final columns = findTableColumns(
        groupHocrLines(parseHocrWords(c.toHocr())),
      )!;
      expect(columns.holes, 9);
    });
  });

  group('placing a row under its columns', () {
    late TableColumns columns;
    late _Card card;

    setUp(() {
      card = _cardWithHeader();
      columns = findTableColumns(
        groupHocrLines(parseHocrWords(card.toHocr())),
      )!;
    });

    PlacedRow place(
      List<int> yards, {
      String label = 'BLACK TEES',
      int? frontSubtotal,
      int? backSubtotal,
      int? total,
      Map<int, String> extra = const {},
    }) {
      final c = _cardWithHeader();
      _teeRow(
        c,
        200,
        label,
        yards,
        frontSubtotal: frontSubtotal,
        backSubtotal: backSubtotal,
        total: total,
        extra: extra,
      );
      final line = groupHocrLines(parseHocrWords(c.toHocr())).last;
      return placeRowByColumns(line, columns)!;
    }

    test('puts every value in its own hole', () {
      final r = place(_black);
      expect(r.yards, _black);
      expect(r.known, 18);
    });

    test('reads the label as the tee name', () {
      expect(place(_red, label: 'RED TEES').name, 'Red');
    });

    test('a lost value leaves its own hole unknown, not the next one', () {
      // This is the whole point. Hole 1 misread as 986 and hole 17 as 9256:
      // both are outside the length a hole can have, so both holes read as
      // unknown and the other sixteen stay on their own holes.
      final garbled = [986, ..._red.sublist(1, 16), 9256, _red[17]];
      final r = place(garbled, label: 'RED TEES');
      expect(r.known, 16);
      expect(r.yards[0], 0, reason: 'hole 1 was not read');
      expect(r.yards[1], 264, reason: 'hole 2 is hole 2');
      expect(r.yards[3], 407);
      expect(r.yards[16], 0, reason: 'hole 17 was not read');
      expect(r.yards[17], 410, reason: 'hole 18 is hole 18');
      // And the holes after the first gap are not the neighbouring hole's
      // value, which is what the text read would have produced.
      expect(r.yards[2], 111);
      expect(r.yards[15], 256);
    });

    test('a value under no column at all is not a yardage', () {
      // Stray text far to the right of the table must not land in hole 18.
      final c = _cardWithHeader();
      // A stray number in the far right margin, under nothing.
      _teeRow(c, 200, 'BLACK TEES', _black, total: 6323, extra: {23: '9999'});
      final line = groupHocrLines(parseHocrWords(c.toHocr())).last;
      final r = placeRowByColumns(line, columns)!;
      expect(r.yards[17], 525);
    });

    test('the card\'s own subtotals are used to check the row', () {
      final good = place(
        _black,
        frontSubtotal: 3100,
        backSubtotal: 3223,
        total: 6323,
      );
      expect(good.subtotals.printed, isTrue);
      expect(good.subtotals.ok, isTrue);
      expect(good.subtotals.front, isTrue);
      expect(good.subtotals.back, isTrue);
      expect(good.subtotals.total, isTrue);
    });

    test('a row that disagrees with its subtotals is reported', () {
      final wrong = [for (final y in _black) y + 1];
      final r = place(
        wrong,
        frontSubtotal: 3100,
        backSubtotal: 3223,
        total: 6323,
      );
      expect(r.subtotals.printed, isTrue);
      expect(r.subtotals.ok, isFalse);
    });

    test('a row with a hole missing has no subtotal opinion', () {
      // A missing hole makes every sum short by an unknown amount, so the
      // printed totals cannot confirm anything. Reporting "no opinion" is what
      // stops this reading as verified.
      final damaged = [986, ..._red.sublist(1, 16), 9256, _red[17]];
      final r = place(
        damaged,
        label: 'RED TEES',
        frontSubtotal: 2358,
        backSubtotal: 2447,
        total: 4805,
      );
      expect(
        r.subtotals.printed,
        isFalse,
        reason: 'the printed totals cannot confirm a row with a hole missing',
      );
    });

    test('a row with a hole missing is not verified', () {
      // The row still has 18 slots after placement, so its length looks
      // whole. The two zeros are what say otherwise, and without them this row
      // would pass as a good read.
      final damaged = [986, ..._red.sublist(1, 16), 9256, _red[17]];
      final c = _cardWithHeader();
      _teeRow(c, 200, 'RED TEES', damaged);
      final r = placeRowByColumns(
        groupHocrLines(parseHocrWords(c.toHocr())).last,
        findTableColumns(groupHocrLines(parseHocrWords(c.toHocr())))!,
      )!;
      expect(r.yards.length, 18);
      expect(r.yards.where((y) => y == 0).length, 2);
      final tee = ScannedTee(
        name: r.name,
        yards: r.yards,
        subtotals: r.subtotals,
      );
      expect(tee.verified, isFalse);
    });

    test('a row with no label is not a tee box', () {
      // A bare line of numbers could be the par row or a stray total, and
      // naming it after its first value would invent a tee called "1".
      final c = _cardWithHeader();
      c.row(200, _pars.map((p) => '$p').toList());
      final line = groupHocrLines(parseHocrWords(c.toHocr())).last;
      expect(placeRowByColumns(line, columns), isNull);
    });
  });

  group('the two passes together', () {
    test('geometry places a shifted row the text read could not', () {
      // The text read of this card loses hole 3's yardage, which renames every
      // hole after it: 16 values in order, all of them in the right order,
      // none of them on the right hole. The geometry pass places 17 of 18 and
      // leaves the lost one unknown. Merged, the merged tee is the geometry
      // one, because it read more holes and agrees with its own subtotals.
      final card = _cardWithHeader();
      // Hole 3's value never reached the page. Its column is empty and every
      // other value is where it belongs.
      _teeRowWithHoleDropped(card, 200, 'BLACK TEES', _black, 2);

      final textScan = parseScorecardText(
        card.lines.map((l) => l.text).join('\n'),
      );
      final geomScan = parseHocrGeometry(card.toHocr(), textScan: textScan);

      final textTee = textScan.tees.first;
      final geomTee = geomScan.tees.first;
      expect(geomTee.yards.length, 18);
      // The text read has 17 values and does not know it is short, so every
      // hole after the gap is off by one: hole 4's yardage sits on hole 3.
      expect(textTee.yards.length, 17);
      expect(
        textTee.yards[2],
        _black[3],
        reason: '516 is hole 4, read as hole 3',
      );
      expect(
        textTee.yards[3],
        _black[4],
        reason: '145 is hole 5, read as hole 4',
      );
      expect(textTee.verified, isFalse);
      // Geometry has 18 slots and knows which one it did not read.
      expect(geomTee.yards[2], 0, reason: 'the lost hole reads as unknown');
      expect(geomTee.yards[3], _black[3], reason: 'and hole 4 stays hole 4');
      // Not verified: geometry knows a hole is missing, which is exactly the
      // difference. The text read is all 18 slots full and still wrong.
      expect(geomTee.verified, isFalse);

      final merged = mergeScans([textScan, geomScan]);
      expect(merged.tees.first.yards[3], _black[3]);
      expect(
        merged.tees.first.yards[2],
        0,
        reason: 'hole 3 is shown as unknown for the user to fill in',
      );
      expect(merged.tees.first.verified, isFalse);
    });

    test('a text read is not thrown away when geometry reads less', () {
      final card = _cardWithHeader();
      _teeRow(
        card,
        200,
        'BLACK TEES',
        _black,
        frontSubtotal: 3100,
        backSubtotal: 3223,
        total: 6323,
        rating: 70.4,
      );
      final textScan = parseScorecardText(
        card.lines.map((l) => l.text).join('\n'),
      );
      // Geometry with nothing to align to: the pass returns an empty read.
      final noGeometry = _Card();
      noGeometry.row(60, ['garbled', 'header']);
      _teeRow(noGeometry, 200, 'BLACK TEES', _black);
      final geomScan = parseHocrGeometry(
        noGeometry.toHocr(),
        textScan: textScan,
      );
      expect(geomScan.tees, isEmpty);

      final merged = mergeScans([textScan, geomScan]);
      expect(merged.tees.first.yards, _black);
      expect(merged.tees.first.verified, isTrue);
    });
  });

  group('reading a whole card from geometry', () {
    test('a clean card comes out right', () {
      final c = _cardWithHeader();
      _teeRow(
        c,
        200,
        'BLACK TEES',
        _black,
        frontSubtotal: 3100,
        backSubtotal: 3223,
        total: 6323,
        rating: 70.4,
      );
      _teeRow(
        c,
        300,
        'RED TEES',
        _red,
        frontSubtotal: 2358,
        backSubtotal: 2447,
        total: 4805,
        rating: 63.6,
      );
      final scan = parseHocrGeometry(c.toHocr());
      expect(scan.tees.length, 2);
      expect(scan.tees.first.name, 'Black');
      expect(scan.tees.first.yards, _black);
      expect(scan.tees.first.verified, isTrue);
      expect(scan.tees.last.yards, _red);
      expect(scan.tees.last.verified, isTrue);
    });

    test('a damaged row keeps the other rows whole', () {
      final c = _cardWithHeader();
      _teeRow(
        c,
        200,
        'BLACK TEES',
        _black,
        frontSubtotal: 3100,
        backSubtotal: 3223,
        total: 6323,
        rating: 70.4,
      );
      final garbled = [986, ..._red.sublist(1, 16), 9256, _red[17]];
      _teeRow(c, 300, 'RED TEES', garbled, rating: 63.6);
      final scan = parseHocrGeometry(c.toHocr());
      final black = scan.tees.firstWhere((t) => t.name == 'Black');
      final red = scan.tees.firstWhere((t) => t.name == 'Red');
      expect(black.verified, isTrue);
      expect(red.yards.where((y) => y == 0).length, 2);
      // The 16 values that did read are on their own holes, which the text
      // read could not do.
      expect(red.yards[1], 264);
      expect(red.yards[17], 410);
    });

    test('par and handicap come from the text read, not from geometry', () {
      final c = _cardWithHeader();
      c.margin(120, 'PAR');
      c.row(120, _pars.map((p) => '$p').toList());
      _teeRow(
        c,
        200,
        'BLACK TEES',
        _black,
        frontSubtotal: 3100,
        backSubtotal: 3223,
        total: 6323,
      );
      final textScan = ScorecardScan(pars: _pars, hcp: const [1, 2, 3]);
      final scan = parseHocrGeometry(c.toHocr(), textScan: textScan);
      expect(scan.pars, _pars);
      expect(scan.hcp, [1, 2, 3]);
      expect(scan.tees.first.yards, _black);
    });

    test('a card with no header yields nothing rather than a guess', () {
      // The bad scan's header read as noise. With no columns there is nothing
      // to align to, and inventing geometry would move values onto the wrong
      // holes, so the pass returns empty and the text read stands alone.
      final c = _Card();
      c.row(60, ['weweoneowos', '19', '3', '4', '5']);
      _teeRow(c, 200, 'BLACK TEES', _black);
      expect(parseHocrGeometry(c.toHocr()).tees, isEmpty);
    });

    test('two blocks of the same tee keep the one that read more', () {
      final c = _cardWithHeader();
      _teeRow(c, 200, 'BLACK TEES', _black.sublist(0, 14), frontSubtotal: 3100);
      _teeRow(
        c,
        600,
        'BLACK TEES',
        _black,
        frontSubtotal: 3100,
        backSubtotal: 3223,
        total: 6323,
      );
      final scan = parseHocrGeometry(c.toHocr());
      expect(scan.tees.length, 1);
      expect(scan.tees.first.yards, _black);
    });
  });
}

/// Reading a scorecard's table geometry from hOCR rather than from text.
///
/// The plain-text OCR result is a flat list of numbers per line, in reading
/// order. That is fine until a digit is lost: with 18 values read and one
/// missing, the 16 surviving values are all still in order, so every hole
/// after the gap is silently renamed. Nothing in the text says hole 2's value
/// should have been hole 1's.
///
/// hOCR carries each word's box, so the numbers can be put back under the
/// header's columns. A value that is missing is then *missing* — the hole it
/// belonged to reads as unknown and the holes after it stay where they are.
/// That is the whole point of doing this: not reading more values, but
/// refusing to shift the ones already read.
library;

/// One recognised word with the box Tesseract gave it, in image pixels.
class HocrWord {
  final String text;
  final int left;
  final int top;
  final int right;
  final int bottom;
  final int confidence;

  const HocrWord({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.confidence,
  });

  int get width => right - left;

  /// A single number, which is all this cares about. "3100" is a number;
  /// "31.4" and "1,300" are not, because a scorecard never prints those in a
  /// yardage column and a rating is handled by its own row.
  int? get number {
    final t = text.trim();
    if (t.isEmpty || t.length > 4) return null;
    if (!RegExp(r'^\d+$').hasMatch(t)) return null;
    return int.tryParse(t);
  }

  /// Horizontal centre, used to decide which column a value belongs to.
  double get centerX => (left + right) / 2;

  /// Vertical centre, used to group words into rows.
  double get centerY => (top + bottom) / 2;
}

/// One row of the table: the words whose boxes sit at the same height.
class HocrLine {
  final List<HocrWord> words;

  HocrLine(this.words);

  /// The words left to right, which is the only order worth keeping.
  List<HocrWord> get ordered =>
      [...words]..sort((a, b) => a.left.compareTo(b.left));

  /// This row's height, used to decide how far a word can drift and still
  /// count as being on the same row.
  double get height {
    final tops = words.map((w) => w.top).toList()..sort();
    final bottoms = words.map((w) => w.bottom).toList()..sort();
    return bottoms.last.toDouble() - tops.first;
  }

  double get top =>
      words.map((w) => w.top).reduce((a, b) => a < b ? a : b).toDouble();

  /// The row as plain text, for the label and line-shape checks that the
  /// existing text parser already does well.
  String get text => ordered.map((w) => w.text).join(' ');

  @override
  String toString() => text;
}

/// Pulls the word boxes out of an hOCR document.
///
/// Tesseract's hOCR is a nest of divs and spans, but only the word spans
/// matter here, and only two things are read off each: the `bbox` in its title
/// and the text it wraps. Matching on the box rather than on a particular
/// class name keeps this working across the Tesseract versions that rename the
/// word class but keep the geometry.
List<HocrWord> parseHocrWords(String hocr) {
  if (hocr.trim().isEmpty) return const [];
  final words = <HocrWord>[];
  // A word span is one whose title carries a box and whose content is plain
  // text with no tags inside it. The `[^<]*` matters: hOCR nests word spans
  // inside line spans, and a line span's own title carries a box too, so
  // matching any span with a bbox would swallow a whole row as one word.
  final span = RegExp(
    r'<span[^>]*\bbbox\b[^>]*>[^<]*</span>',
    dotAll: true,
    caseSensitive: false,
  );
  final bbox = RegExp(
    r'bbox\s+(-?\d+)\s+(-?\d+)\s+(-?\d+)\s+(-?\d+)',
    caseSensitive: false,
  );
  final wconf = RegExp(r'x_wconf\s+(-?\d+)', caseSensitive: false);

  for (final m in span.allMatches(hocr)) {
    final tag = m.group(0)!;
    final box = bbox.firstMatch(tag);
    if (box == null) continue; // a span without geometry carries no position
    final open = tag.indexOf('>');
    final close = tag.lastIndexOf('</span>');
    if (open < 0 || close < open) continue;
    final text = _unescape(tag.substring(open + 1, close)).trim();
    if (text.isEmpty) continue;
    final conf = wconf.firstMatch(tag);
    words.add(
      HocrWord(
        text: text,
        left: int.parse(box.group(1)!),
        top: int.parse(box.group(2)!),
        right: int.parse(box.group(3)!),
        bottom: int.parse(box.group(4)!),
        confidence: int.tryParse(conf?.group(1) ?? '') ?? 0,
      ),
    );
  }
  return words;
}

String _unescape(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&#39;', "'")
    .replaceAll('&amp;', '&');

/// Groups words into the rows they were printed on.
///
/// Words on a scorecard row share a baseline, so grouping by vertical
/// overlap works. The band is grown as words join rather than fixed in
/// advance, because a table row is much taller than a single word and a fixed
/// band either splits tall rows or swallows the row above.
List<HocrLine> groupHocrLines(List<HocrWord> words) {
  if (words.isEmpty) return const [];
  final byHeight = [...words]..sort((a, b) => a.centerY.compareTo(b.centerY));
  final lines = <HocrLine>[];
  var current = <HocrWord>[];
  var top = double.infinity;
  var bottom = double.negativeInfinity;

  for (final w in byHeight) {
    // Overlap of this word with the band so far. A word that clears the
    // middle of the band is on the row; one that sits entirely above or below
    // it starts the next one.
    if (current.isNotEmpty && (w.top > bottom || w.bottom < top)) {
      lines.add(HocrLine(current));
      current = <HocrWord>[];
    }
    current.add(w);
    top = top == double.infinity
        ? w.top.toDouble()
        : (top < w.top ? top : w.top.toDouble());
    bottom = bottom == double.negativeInfinity
        ? w.bottom.toDouble()
        : (bottom > w.bottom ? bottom : w.bottom.toDouble());
  }
  if (current.isNotEmpty) lines.add(HocrLine(current));
  return lines;
}

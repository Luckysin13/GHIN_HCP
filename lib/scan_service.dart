import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// On-device OCR for scorecard photos (Tesseract, fully offline on mobile
/// with the bundled eng.traineddata; web uses tesseract.js, which needs
/// internet on first use). Throws [ScanException] with a user-facing
/// message on any failure.
class ScanException implements Exception {
  final String message;
  const ScanException(this.message);
  @override
  String toString() => message;
}

/// The folder scanned scorecard photos live in, created if needed.
///
/// Shared with the backup restore, so a restored photo lands in the same
/// place the scanner would have put it and a course's imagePath needs no
/// special-casing.
Future<Directory> scorecardPhotoDirectory() async {
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory('${docs.path}/scorecards');
  if (!dir.existsSync()) await dir.create(recursive: true);
  return dir;
}

/// Copies a scanned scorecard photo into persistent app storage so it
/// survives restarts, and returns the path to store on the course.
/// On web there is no app file storage, so the picker's blob URL is
/// returned (viewable for the session, like the rest of web state).
Future<String> persistScanPhoto(XFile file, String courseId) async {
  if (kIsWeb) return file.path;
  final dir = await scorecardPhotoDirectory();
  final dest = '${dir.path}/$courseId.jpg';
  await File(file.path).copy(dest);
  return dest;
}

/// Best-effort delete of a stored photo. Never throws.
Future<void> deleteScanPhoto(String path) async {
  try {
    if (path.isEmpty || kIsWeb) return;
    await File(path).delete();
  } catch (_) {}
}

/// True when [path] currently shows an image (blob URL on web, file on disk).
bool photoUsable(String path) {
  if (path.isEmpty) return false;
  if (kIsWeb) return true;
  try {
    return File(path).existsSync();
  } catch (_) {
    return false;
  }
}

/// How an image is prepared before OCR. Two passes over the same photo
/// fail in different ways, so the scan tries both rather than trusting one
/// preparation for every attempt.
enum ImagePrep {
  /// Grayscale with a percentile contrast stretch. Keeps the grey levels,
  /// so Tesseract's own thresholding still applies.
  stretched,

  /// Grayscale, stretch, then binarize at an adaptive (Otsu) threshold.
  /// Wins on the usual phone-photo problem: uneven light across the card.
  thresholded,
}

/// One OCR attempt: how the photo is prepared plus how Tesseract segments
/// it. Ordered by how often each has been the one that read a real card
/// cleanly, because the scan stops as soon as a parse is good enough.
class ScanVariant {
  final ImagePrep prep;
  final String? psm;
  const ScanVariant(this.prep, this.psm);

  /// Short name for the status line, e.g. "thresholded psm6".
  String get label => '${prep.name}${psm == null ? '' : ' psm$psm'}';
}

/// OCR attempts in order. The first is the historical default; the rest
/// vary preprocessing *and* page segmentation, because a photo that reads
/// badly under one preparation usually reads badly under all of them, and
/// varying only the segmentation just repeats the same failure.
const List<ScanVariant> scanVariants = [
  ScanVariant(ImagePrep.stretched, null),
  ScanVariant(ImagePrep.thresholded, '6'),
  ScanVariant(ImagePrep.stretched, '4'),
  ScanVariant(ImagePrep.thresholded, '11'),
];

/// Adaptive binarization threshold from a luminance histogram (Otsu's
/// method): the value that best splits ink from paper. Beats a fixed
/// cut-off, which a shadowed or glared photo will miss entirely.
double _otsuThreshold(img.Image gray) {
  final hist = List<int>.filled(256, 0);
  for (var y = 0; y < gray.height; y++) {
    for (var x = 0; x < gray.width; x++) {
      hist[gray.getPixel(x, y).luminance.toInt().clamp(0, 255)]++;
    }
  }
  final total = gray.width * gray.height;
  if (total == 0) return 0.5;
  var sum = 0.0;
  for (var i = 0; i < 256; i++) {
    sum += i * hist[i];
  }
  var sumB = 0.0;
  var wB = 0;
  var best = 0.0;
  var bestVar = -1.0;
  for (var t = 0; t < 256; t++) {
    wB += hist[t];
    if (wB == 0) continue;
    final wF = total - wB;
    if (wF == 0) break;
    sumB += t * hist[t];
    final mB = sumB / wB;
    final mF = (sum - sumB) / wF;
    final between = wB * wF * (mB - mF) * (mB - mF);
    if (between > bestVar) {
      bestVar = between;
      best = t.toDouble();
    }
  }
  return (best + 1) / 256.0;
}

/// Phase 2 OCR preprocessing (pure transform, no plugins): fix phone
/// EXIF rotation, grayscale, stretch contrast, and upscale small images so
/// digit height matches what Tesseract expects. Returns null when [bytes]
/// are not a decodable image.
///
/// Contrast is stretched by percentile, not by absolute min/max: one
/// shadow, glare spot or pen scribble otherwise sets the range for the
/// whole photo and the digits wash out.
img.Image? preprocessBytes(
  List<int> bytes, {
  ImagePrep prep = ImagePrep.stretched,
}) {
  try {
    final decoded = img.decodeImage(Uint8List.fromList(bytes));
    if (decoded == null) return null;
    var out = img.bakeOrientation(decoded);
    out = img.grayscale(out);
    out = img.histogramStretch(out, stretchClipRatio: 0.015);
    if (out.width < 2000) {
      out = img.copyResize(
        out,
        width: 2000,
        interpolation: img.Interpolation.cubic,
      );
    }
    if (prep == ImagePrep.thresholded) {
      out = img.luminanceThreshold(out, threshold: _otsuThreshold(out));
    }
    return out;
  } catch (_) {
    return null;
  }
}

/// Runs [preprocessBytes] over a photo file and writes a temp JPEG for
/// OCR. The original photo is untouched (it is what gets saved/viewed).
/// Falls back to [imagePath] on any failure, including web where there
/// is no temp-file OCR path.
Future<String> preprocessScorecard(
  String imagePath, {
  ImagePrep prep = ImagePrep.stretched,
}) async {
  if (kIsWeb) return imagePath;
  try {
    final out = preprocessBytes(
      await File(imagePath).readAsBytes(),
      prep: prep,
    );
    if (out == null) return imagePath;
    final dir = await getTemporaryDirectory();
    final dest = '${dir.path}/score-ocr-${prep.name}.jpg';
    await File(dest).writeAsBytes(img.encodeJpg(out, quality: 95));
    return dest;
  } catch (_) {
    return imagePath;
  }
}

/// Phase 3 engine tuning. Tesseract variables ride the plugin's
/// supported `args` channel (native `setVariable`); the `psm` key selects
/// the page segmentation mode. Kept in code, not UI: A/B via the raw-text
/// inspector, winning values land here.
const Map<String, String> ocrArgs = {
  // Keep table columns apart so yardage rows stay on one line.
  'preserve_interword_spaces': '1',
};

/// Engine arguments for a digits-only pass.
///
/// Tesseract chooses freely among letters and digits unless told otherwise,
/// and on a noisy photo it picks letters for small digits: a par row comes
/// back as "(N v v v e v" rather than "4 4 3 5 3 4". Restricted to digits
/// the same pixels decode as digits, which the par row's arithmetic can then
/// check against the totals the card prints. The pass is run in addition to
/// the normal one, never instead of it — a whitelist destroys the tee names
/// and headings, so its output is only mined for numbers.
const Map<String, String> digitsOnlyArgs = {
  ...ocrArgs,
  'tessedit_char_whitelist': '0123456789 ',
  // A single text line per row, which is how a table is laid out.
  'psm': '6',
};

/// PSM override for A/B tests (null = engine default). Candidates tried
/// against real cards: '6' uniform block, '4' single column, '11' sparse.
const String? ocrPsmOverride = null;

Future<String> extractScorecardText(
  String imagePath, {
  Map<String, String>? args,
}) async {
  try {
    final effective = {
      ...ocrArgs,
      if (ocrPsmOverride != null) 'psm': ocrPsmOverride,
      ...?args,
    };
    final text = await FlutterTesseractOcr.extractText(
      imagePath,
      language: 'eng',
      args: effective,
    );
    if (text.trim().isEmpty) {
      throw const ScanException(
        'No text found in the photo. Try closer, straight-on, and well-lit.',
      );
    }
    return text;
  } on ScanException {
    rethrow;
  } catch (e) {
    throw ScanException(
      'Could not read the photo (${'$e'.split('\n').first}).',
    );
  }
}

/// The same OCR, asked for hOCR instead of plain text, so each word comes
/// back with the box Tesseract put it in.
///
/// Returns null when the platform has no hOCR (iOS) or the call fails, which
/// is not worth reporting: the text pass already ran, and geometry is a
/// refinement rather than the only way to read the card.
///
/// A single text line per row matters more here than for the text pass. The
/// plain read copes with a table split across several blocks; this one needs
/// the rows grouped by their boxes to line up, and a segmentation mode that
/// scatters a table into arbitrary blocks cannot do that.
Future<String?> extractScorecardHocr(String imagePath) async {
  try {
    final hocr = await FlutterTesseractOcr.extractHocr(
      imagePath,
      language: 'eng',
      args: hocrArgs,
    );
    return hocr.trim().isEmpty ? null : hocr;
  } catch (_) {
    return null;
  }
}

/// hOCR is only useful if words come back in rows, so segmentation is forced
/// to a single uniform block of lines rather than left to the engine's
/// page-layout guess, which is what scatters a table on a photo.
const Map<String, String> hocrArgs = {...ocrArgs, 'psm': '6'};

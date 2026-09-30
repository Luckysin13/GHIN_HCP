/// Browser-side half of a backup export, kept in its own library behind a
/// conditional import so none of this compiles into the Android build.
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Saves [contents] as a download named [filename] and reports where the
/// browser put it.
///
/// The blob URL is revoked right after the click. A blob stays alive for the
/// life of the document, so without this a few exports would pin their
/// contents in memory until the tab closed.
String webDownload(String filename, String contents, String mimeType) {
  final parts = [Uint8List.fromList(utf8.encode(contents)).toJS].toJS;
  final blob = web.Blob(parts, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = filename
    ..style.display = 'none';
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
  return 'Downloads/$filename';
}

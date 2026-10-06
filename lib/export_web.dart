/// Browser-side half of a backup export, kept in its own library behind a
/// conditional import so none of this compiles into the Android build.
library;

import 'dart:async';
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

/// Opens the browser's native file picker and reads the selected file directly.
///
/// Reading the `File` through `FileReader` avoids converting it to a blob URL
/// and then fetching that URL again, which can fail in hosted web builds.
Future<String?> webPickFile(List<String> extensions) {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = extensions.map((extension) => '.$extension').join(',');
  input.style
    ..position = 'fixed'
    ..left = '-10000px'
    ..opacity = '0';
  web.document.body!.append(input);

  final result = Completer<String?>();
  void removeInput() => input.remove();

  input.onChange.first.then((_) {
    final file = input.files?.item(0);
    if (file == null) {
      removeInput();
      if (!result.isCompleted) result.complete(null);
      return;
    }

    final reader = web.FileReader();
    reader.onLoadEnd.first.then((_) {
      removeInput();
      if (result.isCompleted) return;
      final error = reader.error;
      if (error != null) {
        result.completeError(StateError(error.message));
        return;
      }
      final contents = reader.result;
      if (contents == null) {
        result.completeError(StateError('The selected file was empty.'));
        return;
      }
      result.complete((contents as JSString).toDart);
    });
    reader.readAsText(file);
  });

  input.addEventListener(
    'cancel',
    ((web.Event _) {
      removeInput();
      if (!result.isCompleted) result.complete(null);
    }).toJS,
  );

  input.click();
  return result.future;
}

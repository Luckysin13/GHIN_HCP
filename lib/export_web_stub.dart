/// Stand-in for the web half of a backup export on platforms with no DOM.
///
/// Selected by the conditional import in `export_io.dart`, so the body is
/// never called; it exists only to keep a real signature for the analyzer.
library;

String webDownload(String filename, String contents, String mimeType) =>
    throw UnsupportedError('webDownload is only available on web');

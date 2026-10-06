import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'export_web_stub.dart'
    if (dart.library.js_interop) 'export_web.dart'
    as web;

/// The Android half of "save as".
///
/// file_selector implements getSaveLocation on web and desktop but not on
/// Android, so the host drives ACTION_CREATE_DOCUMENT itself. See
/// MainActivity.kt.
const MethodChannel _androidBackup = MethodChannel('ghin_golf/backup');

/// What happened to an export.
///
/// Cancelled and failed are kept apart on purpose: backing out of a save
/// dialog is the user changing their mind and deserves no error, while a
/// dialog that opened and then failed is a real problem to report.
sealed class BackupResult {
  const BackupResult();
}

/// The file was written, and [where] says where the user put it.
class BackupWritten extends BackupResult {
  final String where;
  const BackupWritten(this.where);
}

/// The user dismissed the save dialog. Nothing was written, and that is fine.
class BackupCancelled extends BackupResult {
  const BackupCancelled();
}

/// The file could not be written.
class BackupFailed extends BackupResult {
  final String reason;
  const BackupFailed(this.reason);
}

/// A place to write, as the platform describes it.
class _Destination {
  /// A filesystem path, or a `content://` uri when [isContentUri].
  final String location;
  final bool isContentUri;
  const _Destination(this.location, {this.isContentUri = false});
}

/// Asks the user where to save, then writes the file there.
///
/// The user chooses the folder and the name, because "where did that file
/// go" is the single most common way a backup turns out to be useless. The
/// suggested name is the timestamped default, so accepting the dialog as-is
/// still gives a name worth keeping.
///
/// If the platform has no save dialog at all the file goes to the app's
/// Documents directory instead, so exporting is never simply unavailable.
Future<BackupResult> writeBackupFile(
  String filename,
  String contents, {
  String mimeType = 'text/plain',
}) async {
  try {
    if (kIsWeb) {
      return BackupWritten(web.webDownload(filename, contents, mimeType));
    }
    final dest = await _askWhereToSave(filename, mimeType);
    // A null destination means the user backed out.
    if (dest == null) return const BackupCancelled();
    if (dest.isContentUri) {
      final ok = await _androidBackup.invokeMethod<bool>('writeTo', {
        'uri': dest.location,
        'contents': contents,
      });
      if (ok != true) {
        return const BackupFailed('The file could not be written there.');
      }
      return BackupWritten(dest.location);
    }
    await File(dest.location).writeAsString(contents, flush: true);
    return BackupWritten(dest.location);
  } catch (e) {
    return BackupFailed('$e');
  }
}

/// Offers the platform's save dialog. Returns null if the user cancelled.
Future<_Destination?> _askWhereToSave(String filename, String mimeType) async {
  final ext = filename.contains('.')
      ? filename.split('.').last.toLowerCase()
      : 'txt';
  final groups = <XTypeGroup>[
    XTypeGroup(
      label: 'ghin-golf backup',
      extensions: [ext],
      mimeTypes: [mimeType],
    ),
  ];
  if (defaultTargetPlatform == TargetPlatform.android) {
    try {
      final uri = await _androidBackup.invokeMethod<String>('pickDestination', {
        'suggestedName': filename,
        'mimeType': mimeType,
      });
      if (uri == null) return null;
      return _Destination(uri, isContentUri: true);
    } on MissingPluginException {
      // A host without the channel (an older install, or a platform added
      // later) still deserves a working export.
      return _documentsFallback(filename);
    } on PlatformException catch (e) {
      if (e.code == 'unavailable') return _documentsFallback(filename);
      rethrow;
    }
  }
  try {
    final loc = await getSaveLocation(
      suggestedName: filename,
      acceptedTypeGroups: groups,
    );
    if (loc == null) return null;
    return _Destination(loc.path);
  } on UnimplementedError {
    return _documentsFallback(filename);
  }
}

/// Somewhere to put the file when the platform offers no save dialog.
Future<_Destination> _documentsFallback(String filename) async {
  final dir = await getApplicationDocumentsDirectory();
  return _Destination('${dir.path}/$filename');
}

/// Asks the user for a backup file and returns its text, or null if they
/// cancelled or the file could not be read.
///
/// Cancellation is a normal outcome, not a failure, so it returns null
/// quietly. Only a read that actually fails throws, so the caller can tell
/// "no file chosen" from "that file is unreadable".
Future<String?> pickBackupFile({BackupKind kind = BackupKind.json}) async {
  if (kIsWeb) {
    return web.webPickFile(switch (kind) {
      BackupKind.json => const ['json'],
      BackupKind.csv => const ['csv', 'txt'],
    });
  }

  final group = switch (kind) {
    BackupKind.json => const XTypeGroup(
      label: 'ghin-golf backup',
      extensions: ['json'],
      mimeTypes: ['application/json', 'text/plain'],
    ),
    BackupKind.csv => const XTypeGroup(
      label: 'ghin-golf CSV',
      extensions: ['csv', 'txt'],
      mimeTypes: ['text/csv', 'text/plain'],
    ),
  };
  final file = await openFile(acceptedTypeGroups: [group]);
  if (file == null) return null;
  return file.readAsString();
}

/// What [pickBackupFile] is being asked for, which decides the file types the
/// picker offers.
///
/// A separate kind rather than a list of extensions because the two are read by
/// different parsers: offering a .json to the CSV reader would turn a mistyped
/// file into a confusing parse error instead of it simply not being offered.
enum BackupKind { json, csv }

/// `ghin-golf-rounds-20260928-1842.csv`
///
/// The timestamp is baked into the name so a second export does not overwrite
/// the first. A backup that silently replaces the copy you already made is
/// not a backup.
String backupFilename(String extension, {DateTime? at}) {
  final now = at ?? DateTime.now();
  String p(int n) => n.toString().padLeft(2, '0');
  final stamp =
      '${now.year}${p(now.month)}${p(now.day)}'
      '-${p(now.hour)}${p(now.minute)}';
  return 'ghin-golf-rounds-$stamp.$extension';
}

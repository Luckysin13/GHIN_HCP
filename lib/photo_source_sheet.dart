/// Shared camera/gallery picker for scorecard photos attached without OCR.
///
/// The course scanner has its own picker because it feeds Tesseract; this one
/// is for plain attaches: a quick-posted round, an edited round, a course
/// photo added from the Courses page.
library;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// What the scorecard photo sheet returned.
sealed class PhotoPickResult {
  const PhotoPickResult();
}

/// The user picked an image. Callers persist it themselves.
class PhotoPicked extends PhotoPickResult {
  final XFile file;
  const PhotoPicked(this.file);
}

/// The user chose to remove the attached photo.
class PhotoRemoved extends PhotoPickResult {
  const PhotoRemoved();
}

/// Offers Take photo / Choose from gallery, plus Remove photo when
/// [showRemove] is set. Returns null when the sheet is dismissed or the
/// picker itself is cancelled.
Future<PhotoPickResult?> pickScorecardPhoto(
  BuildContext context, {
  bool showRemove = false,
}) async {
  final choice = await showModalBottomSheet<_SheetChoice>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take photo'),
            onTap: () => Navigator.of(ctx).pop(_SheetChoice.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.of(ctx).pop(_SheetChoice.gallery),
          ),
          if (showRemove)
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Remove photo'),
              onTap: () => Navigator.of(ctx).pop(_SheetChoice.remove),
            ),
        ],
      ),
    ),
  );
  switch (choice) {
    case null:
      return null;
    case _SheetChoice.remove:
      return const PhotoRemoved();
    case _SheetChoice.camera:
    case _SheetChoice.gallery:
      final file = await ImagePicker().pickImage(
        source: choice == _SheetChoice.camera
            ? ImageSource.camera
            : ImageSource.gallery,
      );
      if (file == null) return null;
      return PhotoPicked(file);
  }
}

enum _SheetChoice { camera, gallery, remove }

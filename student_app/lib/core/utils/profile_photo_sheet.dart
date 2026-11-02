import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/app_colors.dart';

/// The result of an avatar or logo photo action.
class ProfilePhotoResult {
  final Uint8List? bytes;
  final String? fileName;
  final String? mimeType;
  final bool isRemoved;

  const ProfilePhotoResult._({
    this.bytes,
    this.fileName,
    this.mimeType,
    this.isRemoved = false,
  });

  factory ProfilePhotoResult.picked({
    required Uint8List bytes,
    required String fileName,
    String? mimeType,
  }) =>
      ProfilePhotoResult._(
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
      );

  factory ProfilePhotoResult.removed() =>
      const ProfilePhotoResult._(isRemoved: true);
}

/// Opens a bottom sheet prompting the user to choose an image source or remove their photo.
Future<ProfilePhotoResult?> showProfilePhotoPickerSheet({
  required BuildContext context,
  required String title,
  bool hasExisting = false,
}) async {
  final colors = context.colors;

  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Text(
              title,
              style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from library'),
            onTap: () => Navigator.of(sheetContext).pop('gallery'),
          ),
          if (!kIsWeb)
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.of(sheetContext).pop('camera'),
            ),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Browse files'),
            onTap: () => Navigator.of(sheetContext).pop('files'),
          ),
          if (hasExisting) ...[
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: colors.error),
              title: Text(
                'Remove photo',
                style: TextStyle(color: colors.error, fontWeight: FontWeight.w600),
              ),
              onTap: () => Navigator.of(sheetContext).pop('remove'),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    ),
  );

  if (action == null || !context.mounted) return null;

  if (action == 'remove') {
    return ProfilePhotoResult.removed();
  }

  try {
    if (action == 'gallery' || action == 'camera') {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: action == 'camera' ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (file == null) return null;

      final bytes = await file.readAsBytes();
      if (bytes.lengthInBytes > 2 * 1024 * 1024) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Image must be under 2 MB.'),
              backgroundColor: colors.error,
            ),
          );
        }
        return null;
      }

      final ext = file.name.split('.').last.toLowerCase();
      final mime = _mimeForExt(ext);
      return ProfilePhotoResult.picked(
        bytes: bytes,
        fileName: file.name,
        mimeType: mime,
      );
    } else if (action == 'files') {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'heic'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return null;
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) return null;

      if (bytes.lengthInBytes > 2 * 1024 * 1024) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Image must be under 2 MB.'),
              backgroundColor: colors.error,
            ),
          );
        }
        return null;
      }

      final ext = file.name.split('.').last.toLowerCase();
      final mime = _mimeForExt(ext);
      return ProfilePhotoResult.picked(
        bytes: bytes,
        fileName: file.name,
        mimeType: mime,
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not access image: $e'),
          backgroundColor: colors.error,
        ),
      );
    }
  }

  return null;
}

String _mimeForExt(String ext) {
  switch (ext) {
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    case 'heic':
      return 'image/heic';
    case 'jpg':
    case 'jpeg':
    default:
      return 'image/jpeg';
  }
}

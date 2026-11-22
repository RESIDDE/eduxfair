import 'package:file_picker/file_picker.dart';

/// What a passport document may be, and how to read one off the device.
///
/// Shared by the Documents screen and by answering an institution's request,
/// so the two cannot drift on what they accept.
class DocumentFiles {
  DocumentFiles._();

  static const allowedExtensions = [
    'pdf', 'jpg', 'jpeg', 'png', 'heic', 'doc', 'docx',
  ];

  /// Matches the bucket's own limit, so the student hears about it before
  /// spending their data allowance on the upload.
  static const maxBytes = 20 * 1024 * 1024;

  static String? mimeFor(String? extension) => switch (extension?.toLowerCase()) {
        'pdf' => 'application/pdf',
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'heic' => 'image/heic',
        'doc' => 'application/msword',
        'docx' =>
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        _ => null,
      };

  /// Opens the picker. `withData: true` is essential: on web there is no file
  /// path at all, and bytes are the one approach that works everywhere.
  static Future<PlatformFile?> pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    return result.files.first;
  }
}

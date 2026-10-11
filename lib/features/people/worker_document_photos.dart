import 'dart:typed_data';

/// A retained remote object or a new photo ready for upload.
class WorkerDocumentPhoto {
  const WorkerDocumentPhoto.saved(this.path) : bytes = null, filename = null;
  const WorkerDocumentPhoto.pending(this.bytes, this.filename) : path = null;
  final String? path;
  final Uint8List? bytes;
  final String? filename;
}

List<String> workerDocumentPaths(Map<String, dynamic>? row) {
  final values = row?['attachment_paths'];
  if (values != null && values is! List) {
    throw StateError('書類の写真情報を確認できません。');
  }
  if (values is List && values.isNotEmpty) {
    if (values.any((value) => value is! String || value.trim().isEmpty) ||
        values.toSet().length != values.length) {
      throw StateError('書類の写真情報を確認できません。');
    }
    return List<String>.from(values);
  }
  final path = row?['attachment_path']?.toString().trim() ?? '';
  return path.isEmpty ? const [] : [path];
}

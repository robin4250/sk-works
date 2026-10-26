/// Read-only display evidence from a verified server receipt, never a local
/// photograph, OCR result, upload result, or pending capture draft.
bool savedCapturePhotoRegistered(Map<String, dynamic>? saved) {
  if (saved == null || saved['archived'] == true ||
      saved['id'] is! String || (saved['id'] as String).isEmpty) { return false; }
  final metadata = saved['payload'] is Map ? saved['payload'] as Map : saved;
  final path = metadata['photo_storage_path'];
  return metadata['photo_capture_status'] == 'uploaded' &&
      path is String && path.trim().isNotEmpty;
}

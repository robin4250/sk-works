import '../people/worker_document_photos.dart';

/// Validate an ordered draft against the exact saved photos shown to its owner.
/// Removing an item only changes this selection; no Storage object is deleted.
List<WorkerDocumentPhoto> validateOwnQualificationPhotoSelection({
  required List<WorkerDocumentPhoto> photos,
  required Iterable<String> savedPaths,
}) {
  if (photos.length > 20) throw StateError('写真は20枚以内で選択してください。');
  final allowed = savedPaths.toSet();
  final retained = <String>{};
  for (final photo in photos) {
    final path = photo.path;
    if (path != null) {
      if (!allowed.contains(path) || !retained.add(path)) {
        throw StateError('保存済みの本人資格証写真を確認できません。');
      }
    } else if (photo.bytes == null ||
        photo.bytes!.isEmpty ||
        photo.filename == null ||
        photo.filename!.trim().isEmpty) {
      throw StateError('選択した写真を確認できません。');
    }
  }
  return List.unmodifiable(photos);
}

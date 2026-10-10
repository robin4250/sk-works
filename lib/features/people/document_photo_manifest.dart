/// Pure validation of an ordered, server-owned attachment manifest.
/// A manifest is committed only after every photo upload is confirmed.
class DocumentPhotoEntry {
  const DocumentPhotoEntry({
    required this.path,
    required this.contentType,
  });
  final String path;
  final String contentType;
}

class DocumentPhotoManifest {
  const DocumentPhotoManifest._();

  static List<DocumentPhotoEntry> validate({
    required String companyId,
    required String documentId,
    required Iterable<DocumentPhotoEntry> entries,
  }) {
    if (companyId.isEmpty || documentId.isEmpty ||
        companyId.contains('/') || documentId.contains('/')) {
      throw StateError('Invalid document owner.');
    }
    final prefix = '$companyId/$documentId/';
    final result = <DocumentPhotoEntry>[];
    final seen = <String>{};
    for (final entry in entries) {
      final path = entry.path;
      if (!path.startsWith(prefix) ||
          path.length <= prefix.length ||
          path.contains('..') ||
          path.contains('\\') ||
          !seen.add(path) ||
          !const ['image/jpeg', 'image/png', 'image/heic', 'image/heif']
              .contains(entry.contentType)) {
        throw StateError('Invalid or duplicate document photo.');
      }
      result.add(entry);
    }
    return List.unmodifiable(result);
  }
}

/// Validated ordered metadata for one document's photos.
class DocumentPhotoEntry {
  const DocumentPhotoEntry({
    required this.path,
    required this.contentType,
  });

  final String path;
  final String contentType;

  Map<String, String> toJson() => {
    'path': path,
    'content_type': contentType,
  };

  factory DocumentPhotoEntry.fromJson(Map<String, dynamic> value) {
    if (value['path'] is! String || value['content_type'] is! String) {
      throw StateError('Invalid document photo metadata.');
    }
    return DocumentPhotoEntry(
      path: value['path'] as String,
      contentType: value['content_type'] as String,
    );
  }
}

class DocumentPhotoManifest {
  const DocumentPhotoManifest._();

  static List<DocumentPhotoEntry> decode({
    required String companyId,
    required String documentId,
    required Object? value,
  }) {
    if (value is! List) throw StateError('Invalid photo manifest.');
    return validate(
      companyId: companyId,
      documentId: documentId,
      entries: value.map((item) {
        if (item is! Map) throw StateError('Invalid photo manifest entry.');
        return DocumentPhotoEntry.fromJson(Map<String, dynamic>.from(item));
      }),
    );
  }

  static List<DocumentPhotoEntry> validate({
    required String companyId,
    required String documentId,
    required Iterable<DocumentPhotoEntry> entries,
  }) {
    final safeId = RegExp(r'^[A-Za-z0-9_-]+$');
    if (!safeId.hasMatch(companyId) || !safeId.hasMatch(documentId)) {
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
          path.contains('//') ||
          path.contains('?') ||
          path.contains('#') ||
          path.contains('\\') ||
          path.endsWith('/') ||
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

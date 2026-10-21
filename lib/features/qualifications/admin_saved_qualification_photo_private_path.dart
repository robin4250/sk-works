import 'dart:io';

/// Private-sandbox confinement check, not a native O_NOFOLLOW open guarantee
/// against a hostile concurrent filesystem writer. Mobile adapter checks before
/// and after sqflite opens its distinct connection.
Future<void> verifyAdminQualificationPrivatePath(
  String root,
  String path,
) async {
  if (!root.startsWith('/') ||
      root == '/' ||
      root.endsWith('/') ||
      root.contains('\\') ||
      root.codeUnits.any((c) => c < 32 || c == 127) ||
      root.split('/').skip(1).any((c) => c.isEmpty || c == '.' || c == '..') ||
      path != '$root/sko-qualification-photo-pending-v1.sqlite3' ||
      await Directory(root).resolveSymbolicLinks() != root) {
    throw StateError('Canonical private qualification DB path required');
  }
  for (final candidate in [path, '$path-wal', '$path-shm', '$path-journal']) {
    final type = await FileSystemEntity.type(candidate, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      throw StateError('Qualification DB or sidecar is not a regular file');
    }
    if (type == FileSystemEntityType.file &&
        await File(candidate).resolveSymbolicLinks() != candidate) {
      throw StateError('Qualification DB path escaped private directory');
    }
  }
}

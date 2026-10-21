// Pure Dart filesystem boundary verifier. No plugin, Flutter or application data.
import 'dart:io';

import 'package:sk_works/features/qualifications/admin_saved_qualification_photo_private_path.dart';

Future<void> main() async {
  final temp = await Directory.systemTemp.createTemp('sko-private-path-');
  final root = await temp.resolveSymbolicLinks();
  final path = '$root/sko-qualification-photo-pending-v1.sqlite3';
  int checks = 0;
  Future<void> refused(String selected, String database) async {
    try {
      await verifyAdminQualificationPrivatePath(selected, database);
    } catch (_) {
      checks++;
      return;
    }
    throw StateError('Unexpected path acceptance');
  }

  try {
    await verifyAdminQualificationPrivatePath(root, path);
    checks++;
    await File(path).writeAsString('fixture');
    await verifyAdminQualificationPrivatePath(root, path);
    checks++;
    await refused(root, '$root/other.sqlite3');
    await refused('$root/../other', path);
    await refused('$root/', path);
    final alias = Link('$root/alias');
    await alias.create(root);
    await refused(
      alias.path,
      '${alias.path}/sko-qualification-photo-pending-v1.sqlite3',
    );
    await Link('$path-wal').create('$root/absent');
    await refused(root, path);
    await Link('$path-wal').delete();
    await Directory('$path-shm').create();
    await refused(root, path);
    stdout.writeln(
      'PASS $checks pure filesystem confinement assertions; no mobile binding execution',
    );
  } finally {
    await temp.delete(recursive: true);
  }
}

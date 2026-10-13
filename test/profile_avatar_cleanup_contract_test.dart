import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('avatar replacement swaps metadata before deleting old object', () {
    final source =
        File('lib/features/profile/profile_repository.dart').readAsStringSync();

    final oldPathIndex = source.indexOf("select('avatar_storage_path')");
    final uploadIndex = source.indexOf('uploadBinary', oldPathIndex);
    final profileUpdateIndex =
        source.indexOf("from('user_profiles').upsert", uploadIndex);
    final oldRemoveIndex =
        source.indexOf('remove([oldPath])', profileUpdateIndex);
    final rollbackRemoveIndex =
        source.indexOf('remove([path])', profileUpdateIndex);

    expect(oldPathIndex, greaterThanOrEqualTo(0));
    expect(uploadIndex, greaterThan(oldPathIndex));
    expect(profileUpdateIndex, greaterThan(uploadIndex));
    expect(oldRemoveIndex, greaterThan(profileUpdateIndex));
    expect(rollbackRemoveIndex, greaterThan(profileUpdateIndex));
    expect(source, contains('upsert: false'));
  });
}

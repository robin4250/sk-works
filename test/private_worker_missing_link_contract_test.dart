import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('private worker views fail closed when current worker link is absent', () {
    for (final path in [
      'lib/features/people/worker_document_repository.dart',
      'lib/features/qualifications/qualification_certificate_repository.dart',
      'lib/features/qualifications/qualification_cloud_repository.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        contains('ownWorkerId == null || ownWorkerId.isEmpty'),
        reason: path,
      );
      expect(
        source,
        contains("'workers': const <Map<String, dynamic>>[]"),
        reason: path,
      );
    }
  });
}

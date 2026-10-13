import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('qualification certificate supports optional front and back images', () {
    final repository = File(
      'lib/features/qualifications/qualification_certificate_repository.dart',
    ).readAsStringSync();
    final migration = File(
      'supabase/migrations/20260930195937_add_qualification_certificate_back_image.sql',
    ).readAsStringSync();

    expect(migration, contains('attachment_back_path text'));
    expect(repository, contains('uploadCertificateBack'));
    expect(repository, contains('removeCertificateBack'));
    expect(repository, contains('attachment_back_path'));
    expect(repository, contains('attachment_path'));
  });
}

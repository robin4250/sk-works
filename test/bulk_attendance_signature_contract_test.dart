import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bulk attendance requires one shared handwritten signature', () {
    final page =
        File('lib/features/attendance/bulk_attendance_page.dart').readAsStringSync();
    final repository = File(
      'lib/features/attendance/attendance_cloud_repository.dart',
    ).readAsStringSync();

    expect(page, contains('SignatureCapturePage'));
    expect(page, contains("'signerName': signature.signerName"));
    expect(page, contains("'signatureJson': signature.toJson()"));
    expect(page, contains("'signedAt': signedAt"));
    expect(page, contains('まとめてサインして登録'));

    expect(repository, contains("'signer_name':"));
    expect(repository, contains("'signature_json':"));
    expect(repository, contains("'signed_at':"));
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bulk attendance uses current attendance schema and keeps signatures in daily reports', () {
    final page =
        File('lib/features/attendance/bulk_attendance_page.dart').readAsStringSync();
    final repository = File(
      'lib/features/attendance/attendance_cloud_repository.dart',
    ).readAsStringSync();

    expect(page, contains("'まとめて登録'"));
    expect(page, contains('責任者サインは日報で登録します'));
    expect(page, isNot(contains('SignatureCapturePage')));
    expect(page, isNot(contains("'signatureJson'")));
    expect(page, isNot(contains("'signedAt'")));

    expect(repository, isNot(contains("'signer_name':")));
    expect(repository, isNot(contains("'signature_json':")));
    expect(repository, isNot(contains("'signed_at':")));
  });
}

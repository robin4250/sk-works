import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('past bulk attendance signs once and submits through approval', () {
    final page =
        File('lib/features/attendance/bulk_attendance_page.dart').readAsStringSync();
    final repository = File(
      'lib/features/attendance/attendance_cloud_repository.dart',
    ).readAsStringSync();

    expect(page, contains("'まとめてサインして申請'"));
    expect(page, contains('SignatureCapturePage'));
    expect(page, contains('approvalRepository.submit'));
    expect(page, contains('承認完了後に正式な出勤データへ反映'));

    // Current attendance schema keeps signature data out of attendance_entries.
    expect(repository, isNot(contains("'signer_name':")));
    expect(repository, isNot(contains("'signature_json':")));
    expect(repository, isNot(contains("'signed_at':")));
  });
}

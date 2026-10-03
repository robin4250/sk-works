import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('past bulk attendance signs once and submits for approval', () {
    final page =
        File('lib/features/attendance/bulk_attendance_page.dart').readAsStringSync();
    final repository = File(
      'lib/features/attendance/past_attendance_request_repository.dart',
    ).readAsStringSync();

    expect(page, contains('SignatureCapturePage'));
    expect(page, contains('まとめてサインして申請'));
    expect(page, contains('approvalRepository.submit'));
    expect(page, isNot(contains('widget.repository.insertMany(records)')));
    expect(repository, contains('submit_past_attendance_request'));
    expect(repository, contains('required Object signatureJson'));
    expect(page, contains('承認完了後に正式な出勤データへ反映'));
  });
}

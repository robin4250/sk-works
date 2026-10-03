import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('approval hub includes daily report, attendance correction and onboarding approvals', () {
    final source =
        File('lib/features/approvals/approvals_hub_page.dart').readAsStringSync();

    expect(source, contains('日報の承認待ち'));
    expect(source, contains('勤務修正の承認待ち'));
    expect(source, contains('AttendanceCorrectionApprovalsPage'));
    expect(source, contains('従業員の本登録承認'));
  });
}

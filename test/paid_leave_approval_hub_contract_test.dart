import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('approval hub includes paid leave without restoring separate onboarding entry', () {
    final source =
        File('lib/features/approvals/approvals_hub_page.dart').readAsStringSync();
    expect(source, contains('有給申請の承認待ち'));
    expect(source, contains('PaidLeaveApprovalsPage'));
    expect(source, contains('勤務修正の承認待ち'));
    expect(source, contains('従業員の本登録承認'));
  });
}

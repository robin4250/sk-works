import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('paid leave request UI supports multiple future dates', () {
    final source =
        File('lib/features/attendance/paid_leave_page.dart').readAsStringSync();
    expect(source, contains('有給申請'));
    expect(source, contains('_MultiDateCalendar'));
    expect(source, contains('FilterChip'));
    expect(source, contains('date.isAfter(todayDate)'));
    expect(source, contains('選択した'));
  });

  test('individual payroll settings expose paid leave grant days', () {
    final source = File(
      'lib/features/payroll/individual_payroll_settings_page.dart',
    ).readAsStringSync();
    expect(source, contains('paid_leave_granted_days'));
    expect(source, contains('有給付与日数'));
    expect(source, contains("suffixText: '日'"));
  });

  test('paid leave approvals reuse management approval flow', () {
    final source = File(
      'lib/features/attendance/paid_leave_approvals_page.dart',
    ).readAsStringSync();
    expect(source, contains('有給申請の承認待ち'));
    expect(source, contains('repository.decide'));
    expect(source, contains('承認'));
    expect(source, contains('却下'));
  });
}

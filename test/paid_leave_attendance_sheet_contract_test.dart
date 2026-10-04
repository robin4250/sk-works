import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('attendance sheet shows paid leave in week and month without daily report', () {
    final page = File(
      'lib/features/attendance/worker_attendance_sheet_page.dart',
    ).readAsStringSync();
    final repository = File(
      'lib/features/attendance/worker_attendance_sheet_repository.dart',
    ).readAsStringSync();

    expect(page, contains("'有給申請'"));
    expect(page, contains('paidLeaveOrdinal'));
    expect(page, contains('paidLeaveRemaining'));
    expect(page, contains("paidLeave ? '有給'"));
    expect(page, contains('day?.paidLeave == true ? () {}'));
    expect(repository, contains(".from('paid_leave_requests')"));
    expect(repository, contains(".eq('status', 'approved')"));
    expect(repository, contains('paid_leave_worker_summary'));
  });
}

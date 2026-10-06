import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('paid leave approval notification opens paid leave approvals', () {
    final source = File(
      'lib/features/notifications/notifications_page.dart',
    ).readAsStringSync();
    expect(source, contains("item.actionKey == 'paid_leave_request'"));
    expect(source, contains('PaidLeaveApprovalsPage'));
    expect(source, contains("item.actionKey == 'paid_leave_request'"));
  });

  test('attendance correction notification opens target approval', () {
    final source = File(
      'lib/features/notifications/notifications_page.dart',
    ).readAsStringSync();
    final approvals = File(
      'lib/features/attendance/attendance_correction_approvals_page.dart',
    ).readAsStringSync();

    expect(source, contains("item.actionKey == 'attendance_correction_request'"));
    expect(source, contains('initialRequestId: item.actionId'));
    expect(approvals, contains('this.initialRequestId'));
    expect(approvals, contains('if (item.id == initialRequestId)'));
  });
}

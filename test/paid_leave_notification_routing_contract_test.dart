import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('paid leave approval notification opens paid leave approvals', () {
    final source = File(
      'lib/features/notifications/notifications_page.dart',
    ).readAsStringSync();
    expect(source, contains("item.actionKey == 'paid_leave_request'"));
    expect(source, contains('PaidLeaveApprovalsPage'));
  });
}

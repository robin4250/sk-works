import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('home attention counts paid leave approvals only for authorized approvers', () {
    final repository =
        File('lib/features/home/home_attention_repository.dart').readAsStringSync();
    final content =
        File('lib/features/home/friendly_home_content.dart').readAsStringSync();

    final center = File(
      'lib/features/notifications/attention_center_repository.dart',
    ).readAsStringSync();
    expect(repository, contains('AttentionCenterRepository'));
    expect(repository, contains('await _repository.load()'));
    expect(center, contains('pending_paid_leave_request_batches'));
    expect(center, contains("readSource('paid_leave'"));
    expect(repository, contains('paidLeaveApprovalCount'));
    expect(repository, contains('unresolvedCount'));
    expect(repository, contains('data.snapshot.unresolvedCount'));
    expect(content, contains("widget.onOpen('notifications')"));
    expect(content, isNot(contains("? 'approvals'")));
    expect(content, contains('attention.unresolvedCount'));
  });
}

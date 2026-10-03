import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('home attention counts paid leave approvals only for authorized approvers', () {
    final repository =
        File('lib/features/home/home_attention_repository.dart').readAsStringSync();
    final content =
        File('lib/features/home/friendly_home_content.dart').readAsStringSync();

    expect(repository, contains('pending_paid_leave_request_batches'));
    expect(repository, contains('paidLeaveApprovalCount'));
    expect(repository, contains('unresolvedCount'));
    expect(content, contains("? 'approvals'"));
    expect(content, contains('attention.unresolvedCount'));
  });
}

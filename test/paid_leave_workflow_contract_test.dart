import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('paid leave workflow protects balance and approval state', () {
    final sql = File(
      'supabase/migrations/20260930010500_add_paid_leave_workflow.sql',
    ).readAsStringSync();

    expect(sql, contains('submit_paid_leave_request'));
    expect(sql, contains('approve_paid_leave_request'));
    expect(sql, contains("raise exception 'paid leave balance exceeded'"));
    expect(sql, contains("v_request.status <> 'pending'"));
    expect(sql, contains('used_days = used_days + v_request.days'));
    expect(sql, contains("set status = 'approved'"));
    expect(sql, contains('approved_by = p_approver_id'));
  });
}

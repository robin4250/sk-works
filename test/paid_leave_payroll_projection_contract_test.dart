import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('approved paid leave remains replayable for future payroll', () {
    final sql = File(
      'supabase/migrations/20261003171000_add_paid_leave_payroll_projection.sql',
    ).readAsStringSync();
    expect(sql, contains('approved_paid_leave_payroll_rows'));
    expect(sql, contains('security_invoker = true'));
    expect(sql, contains("where r.status = 'approved'"));
    expect(sql, contains('r.leave_date'));
    expect(sql, contains('1::numeric as paid_leave_days'));
    expect(sql, isNot(contains('paid_leave_amount')));
  });
}

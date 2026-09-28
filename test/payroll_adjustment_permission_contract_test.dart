import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('payroll adjustment permissions stay separate from full payroll access', () {
    final sql = File(
      'supabase/migrations/20260929190500_add_payroll_adjustment_foundation.sql',
    ).readAsStringSync();

    expect(sql, contains('can_view_payroll_adjustments'));
    expect(sql, contains('can_manage_payroll_adjustments'));
    expect(sql, contains('current_payroll_adjustment_permissions'));
    expect(sql, contains('set_payroll_adjustment_permissions'));
    expect(sql, contains("'owner','admin'"));
    expect(sql, contains("'can_rename_page', false"));
  });

  test('payroll adjustment foundation keeps history and company-defined labels', () {
    final sql = File(
      'supabase/migrations/20260929190500_add_payroll_adjustment_foundation.sql',
    ).readAsStringSync();

    expect(sql, contains('company_payroll_adjustment_settings'));
    expect(sql, contains("default '給与調整'"));
    expect(sql, contains('payroll_adjustment_types'));
    expect(sql, contains('payroll_adjustments'));
    expect(sql, contains('label_snapshot'));
    expect(sql, contains('cancelled_at'));
    expect(sql, contains('cancelled_by'));
    expect(sql, contains("direction in ('addition','deduction')"));
  });
}

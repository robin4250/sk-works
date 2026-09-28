import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('payroll adjustment permissions stay separate from full payroll access', () {
    final sql = read(
      'supabase/migrations/20260929034500_add_payroll_adjustment_permissions.sql',
    );

    expect(sql, contains('can_view_payroll_adjustments'));
    expect(sql, contains('can_manage_payroll_adjustments'));
    expect(sql, contains("p_role = 'manager'"));
    expect(sql, contains("p_role = 'viewer'"));
    expect(sql, contains("'can_manage_payroll', false"));
  });

  test('payroll adjustment permissions appear in admin permission UI', () {
    final page = read('lib/features/people/member_permission_page.dart');
    final repository =
        read('lib/features/people/member_permission_repository.dart');

    expect(page, contains('給与調整を閲覧'));
    expect(page, contains('給与調整を登録・編集'));
    expect(page, contains("'can_manage_payroll_adjustments'"));
    expect(repository, contains("'can_view_payroll_adjustments'"));
    expect(repository, contains("'can_manage_payroll_adjustments'"));
  });

  test('payroll adjustment page label is admin-controlled and audited', () {
    final sql = read(
      'supabase/migrations/20260929034500_add_payroll_adjustment_permissions.sql',
    );

    expect(sql, contains('set_payroll_adjustment_page_label'));
    expect(sql, contains("cm.role::text in ('owner','admin')"));
    expect(sql, contains("'page_label_change'"));
    expect(sql, contains('payroll_adjustment_audit_log'));
  });
}

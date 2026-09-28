import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('payroll adjustment permissions stay separate from full payroll access', () {
    final base = read(
      'supabase/migrations/20260929190500_add_payroll_adjustment_foundation.sql',
    );
    final extension = read(
      'supabase/migrations/20260929201500_extend_payroll_adjustment_management.sql',
    );

    expect(base, contains('can_view_payroll_adjustments'));
    expect(base, contains('can_manage_payroll_adjustments'));
    expect(extension, contains("cm.role::text = 'manager'"));
    expect(extension, contains("cm.role::text in ('manager','viewer')"));
    expect(extension, contains('set_payroll_adjustment_permissions'));
  });

  test('payroll adjustment permissions appear in admin permission UI', () {
    final page = read('lib/features/people/member_permission_page.dart');
    final repository =
        read('lib/features/people/member_permission_repository.dart');

    expect(page, contains('給与調整を閲覧'));
    expect(page, contains('給与調整を登録・編集'));
    expect(page, contains("'can_manage_payroll_adjustments'"));
    expect(repository, contains('company_payroll_adjustment_permission_rows'));
    expect(repository, contains('set_payroll_adjustment_permissions'));
  });

  test('payroll adjustment page label and writes are audited', () {
    final sql = read(
      'supabase/migrations/20260929201500_extend_payroll_adjustment_management.sql',
    );

    expect(sql, contains('set_payroll_adjustment_page_label'));
    expect(sql, contains('payroll_adjustment_audit_log'));
    expect(sql, contains("'page_label_change'"));
    expect(sql, contains("'adjustment_create'"));
    expect(sql, contains("'adjustment_cancel'"));
    expect(sql, contains("'permission_change'"));
  });

  test('direct payroll adjustment writes are removed in favor of audited RPCs', () {
    final sql = read(
      'supabase/migrations/20260929201500_extend_payroll_adjustment_management.sql',
    );

    expect(sql, contains('drop policy if exists "authorized managers manage payroll adjustment types"'));
    expect(sql, contains('drop policy if exists "authorized managers manage payroll adjustments"'));
    expect(sql, contains('create_payroll_adjustment'));
    expect(sql, contains('cancel_payroll_adjustment'));
    expect(sql, contains('upsert_payroll_adjustment_type'));
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/home/home_membership_repository.dart';

void main() {
  test('full admin approval access follows configured permission value', () {
    const adminNotAssignee = HomeIdentity(
      role: 'admin',
      companyName: 'SKO',
      displayName: 'Admin',
      permissions: {
        'can_approve_daily_report_edits': false,
      },
    );
    const adminAssignee = HomeIdentity(
      role: 'admin',
      companyName: 'SKO',
      displayName: 'Admin',
      permissions: {
        'can_approve_daily_report_edits': true,
      },
    );

    expect(
      adminNotAssignee.can('can_approve_daily_report_edits'),
      isFalse,
    );
    expect(
      adminAssignee.can('can_approve_daily_report_edits'),
      isTrue,
    );
    expect(adminNotAssignee.can('can_view_invoices'), isTrue);
  });

  test('legacy non-admin financial permissions are cleaned up', () {
    final sql = File(
      'supabase/migrations/20260922021500_align_approval_assignee_permission_source.sql',
    ).readAsStringSync();

    expect(sql, contains("cm.role::text in ('manager','viewer')"));
    expect(sql, contains('can_view_invoices = false'));
    expect(sql, contains('can_manage_invoices = false'));
    expect(sql, contains('can_view_admin_site_data = false'));
    expect(sql, contains('can_manage_admin_site_data = false'));
    expect(sql, contains('can_manage_payroll = false'));
  });

  test('current approval permission follows configured assignee table', () {
    final sql = File(
      'supabase/migrations/20260922021500_align_approval_assignee_permission_source.sql',
    ).readAsStringSync();

    expect(sql, contains('company_approval_assignees'));
    expect(sql, contains('v_is_approval_assignee'));
    expect(
      sql,
      contains("'can_approve_daily_report_edits', v_is_approval_assignee"),
    );
    expect(
      sql,
      isNot(
        contains("'can_approve_daily_report_edits', v_role = 'manager'"),
      ),
    );
  });

  test('approval UI remains driven by current feature permission', () {
    final source = File('lib/app_v2.dart').readAsStringSync();

    expect(
      source,
      contains("_identity.can('can_approve_daily_report_edits')"),
    );
  });
}

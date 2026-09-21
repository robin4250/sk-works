import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  group('pre-device security contracts', () {
    test('secondary password locks after five failures', () {
      final sql = read(
        'supabase/migrations/20260919193000_add_secure_admin_onboarding.sql',
      );
      expect(sql, contains('failed_attempts + 1 >= 5'));
      expect(sql, contains("interval '5 minutes'"));
      expect(
        sql,
        contains(
          'revoke all on public.user_secondary_credentials from anon, authenticated',
        ),
      );
    });

    test('daily report approvers are configurable from one to three', () {
      final sql = read(
        'supabase/migrations/20260921220500_configurable_daily_report_approvers.sql',
      );

      expect(sql, contains('company_approval_assignees'));
      expect(sql, contains('approval_assignee_limit_reached'));
      expect(sql, contains('at_least_one_approval_assignee_required'));
      expect(sql, contains("alter column approvals_required set default 1"));
      expect(sql, contains('v_assignee_count > 1'));
      expect(
        sql,
        contains('single configured approval assignee'),
      );
    });

    test('payroll privacy keeps worker-self or authorized manager rule', () {
      final sql = read(
        'supabase/migrations/20260920020000_harden_financial_privacy.sql',
      );
      expect(
        sql,
        contains('worker or authorized manager can read payroll statements'),
      );
      expect(sql, contains('w.user_id = auth.uid()'));
      expect(sql, contains("can_manage_payroll"));
    });

    test('financial features require explicit feature permissions', () {
      final sql = read(
        'supabase/migrations/20260920020000_harden_financial_privacy.sql',
      );
      expect(sql, contains("can_view_invoices"));
      expect(sql, contains("can_manage_invoices"));
      expect(sql, contains("can_view_admin_site_data"));
      expect(sql, contains("can_manage_admin_site_data"));
    });
  });
}

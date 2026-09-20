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

    test('daily report edit requires two approvals and blocks self approval', () {
      final base = read(
        'supabase/migrations/20260919220000_add_daily_reports_and_approval.sql',
      );
      final hardening = read(
        'supabase/migrations/20260920022000_harden_attendance_and_approval_privacy.sql',
      );

      expect(base, contains('approvals_required integer not null default 2'));
      expect(hardening, contains('requester cannot approve own request'));
      expect(hardening, contains('v_approve_count >= v_required'));
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

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recent operational tables do not keep excess anon or destructive grants', () {
    final migration = File(
      'supabase/migrations/20261004175148_revoke_recent_public_table_excess_privileges.sql',
    ).readAsStringSync();

    for (final table in [
      'attendance_correction_items',
      'attendance_correction_requests',
      'generation_setting_issues',
      'partner_payment_settings',
      'payment_certificates',
    ]) {
      expect(
        migration,
        contains('revoke all privileges on table public.$table from anon'),
      );
    }

    expect(
      migration,
      contains(
        'revoke insert, update, delete, truncate, references, trigger\n'
        'on table public.approved_paid_leave_payroll_rows from authenticated',
      ),
    );
    expect(
      migration,
      contains(
        'revoke delete, truncate, references, trigger\n'
        'on table public.attendance_correction_requests from authenticated',
      ),
    );
  });
}

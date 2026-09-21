import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('migration guard requires latest onboarding and approval migrations', () {
    final source = File('tool/check_migration_files.sh').readAsStringSync();

    for (final name in [
      '20260921220500_configurable_daily_report_approvers.sql',
      '20260922002000_add_employee_invite_foundation.sql',
      '20260922004500_add_employee_onboarding_profile_and_approval.sql',
      '20260922010000_add_required_document_attention.sql',
      '20260922013000_add_admin_initial_setup_wizard.sql',
    ]) {
      expect(source, contains(name));
    }
  });

  test('Supabase reproducibility preflight verifies semantic production state', () {
    final source =
        File('tool/supabase_repro_preflight.sh').readAsStringSync();

    expect(source, contains('supabase_security_assertions.sql'));
    expect(source, contains('production_security_assertions.txt'));
    expect(source, contains('production_capability_markers.tsv'));
    expect(source, contains('company_approval_assignees'));
    expect(source, contains('employee_registration_invites'));
    expect(source, contains('company_initial_setup_progress'));
    expect(source, contains('company_rate_settings'));
    expect(source, contains('nearest_station'));
    expect(source, contains('employee-onboarding-documents'));
    expect(source, contains('t|t|t|t|t|t'));
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Master recovery foundation requires two distinct private contacts', () {
    final sql = File(
      'supabase/migrations/20260930111000_add_master_emergency_recovery_foundation.sql',
    ).readAsStringSync();

    expect(sql, contains('private.master_recovery_contacts'));
    expect(sql, contains('private.master_recovery_challenges'));
    expect(sql, contains('master_recovery_distinct_emails'));
    expect(sql, contains('recovery emails must be different'));
    expect(sql, contains('public.current_master_device_status(p_device_key)'));
    expect(sql, contains('trusted master device required'));
    expect(sql, contains('master_recovery_contacts_update'));
    expect(sql, contains('private.master_admin_audit_log'));
    expect(sql, contains('from public, anon'));
  });

  test('Master recovery app-facing state masks email addresses and exposes no codes', () {
    final sql = File(
      'supabase/migrations/20260930111000_add_master_emergency_recovery_foundation.sql',
    ).readAsStringSync();

    expect(sql, contains('primary_masked'));
    expect(sql, contains('secondary_masked'));
    expect(sql, contains("left(v_row.primary_email,1) || '***@'"));
    expect(sql, isNot(contains("'primary_code_hash',")));
    expect(sql, isNot(contains("'secondary_code_hash',")));
  });
}

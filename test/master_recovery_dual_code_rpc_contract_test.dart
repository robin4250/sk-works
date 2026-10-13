import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Master recovery challenge issuance is service-role only', () {
    final sql = File(
      'supabase/migrations/20260930112000_add_master_recovery_dual_code_rpc.sql',
    ).readAsStringSync();

    expect(sql, contains('public.service_create_master_recovery_challenge'));
    expect(sql, isNot(contains('auth.role()')));
    expect(sql, contains('two distinct six digit codes required'));
    expect(sql, contains("crypt(p_primary_code, gen_salt('bf'))"));
    expect(sql, contains("crypt(p_secondary_code, gen_salt('bf'))"));
    expect(sql, contains('from public, anon, authenticated'));
    expect(sql, contains('to service_role'));
    expect(sql, contains('Execution is restricted to service_role by function ACL'));
  });

  test('Master recovery requires both codes before device registration', () {
    final sql = File(
      'supabase/migrations/20260930112000_add_master_recovery_dual_code_rpc.sql',
    ).readAsStringSync();

    expect(sql, contains('public.verify_master_recovery_code'));
    expect(sql, contains('failed_attempts+1 >= 8'));
    expect(sql, contains('master_recovery_code_failed'));
    expect(sql, contains('master_recovery_code_verified'));
    expect(sql, contains('public.consume_master_recovery_challenge'));
    expect(sql, contains('both recovery codes required'));
    expect(sql, contains('primary_verified_at is null'));
    expect(sql, contains('secondary_verified_at is null'));
    expect(sql, contains('master_recovery_device_registered'));
    expect(sql, contains('used_at=now()'));
  });

  test('app-facing recovery RPCs do not expose raw code hashes', () {
    final sql = File(
      'supabase/migrations/20260930112000_add_master_recovery_dual_code_rpc.sql',
    ).readAsStringSync();

    expect(sql, isNot(contains("'primary_code_hash',v_row.primary_code_hash")));
    expect(sql, isNot(contains("'secondary_code_hash',v_row.secondary_code_hash")));
  });
}

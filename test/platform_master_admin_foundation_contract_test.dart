import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('platform master admin cannot be granted by normal app users', () {
    final sql = File(
      'supabase/migrations/20260929214500_add_platform_master_admin_foundation.sql',
    ).readAsStringSync();

    expect(sql, contains('platform_master_admins'));
    expect(sql, contains('revoke all on public.platform_master_admins'));
    expect(sql, contains('Intentionally no authenticated INSERT/UPDATE/DELETE policy'));
    expect(sql, isNot(contains('grant execute on function public.set_platform_master_admin')));
  });

  test('platform master status and audit access are isolated', () {
    final sql = File(
      'supabase/migrations/20260929214500_add_platform_master_admin_foundation.sql',
    ).readAsStringSync();

    expect(sql, contains('is_platform_master_admin'));
    expect(sql, contains('platform_master_admin_status'));
    expect(sql, contains('platform_master_audit_log'));
    expect(sql, contains('master admins can read platform audit'));
  });
}

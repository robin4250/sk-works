import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('master admin role is isolated from company admin permissions', () {
    final sql = File(
      'supabase/migrations/20260929220000_add_master_admin_role_foundation.sql',
    ).readAsStringSync();

    expect(sql, contains('private.master_admins'));
    expect(sql, contains('revoke all on private.master_admins'));
    expect(sql, contains('is_current_user_master_admin'));
    expect(sql, contains('current_master_admin_status'));
    expect(sql, isNot(contains('set_member_feature_permissions')));
  });

  test('master admin foundation includes protected audit storage', () {
    final sql = File(
      'supabase/migrations/20260929220000_add_master_admin_role_foundation.sql',
    ).readAsStringSync();

    expect(sql, contains('private.master_admin_audit_log'));
    expect(sql, contains('revoke all on private.master_admin_audit_log'));
    expect(sql, contains('actor_user_id'));
    expect(sql, contains('target_user_id'));
    expect(sql, contains('details jsonb'));
  });
}

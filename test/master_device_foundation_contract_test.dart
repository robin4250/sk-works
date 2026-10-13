import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('master devices are private and visible only to master admins', () {
    final sql = File(
      'supabase/migrations/20260929221500_add_master_device_foundation.sql',
    ).readAsStringSync();

    expect(sql, contains('private.master_devices'));
    expect(sql, contains('revoke all on private.master_devices'));
    expect(sql, contains('master_device_rows'));
    expect(sql, contains('is_current_user_master_admin'));
  });

  test('master device lock and revoke actions are audited', () {
    final sql = File(
      'supabase/migrations/20260929221500_add_master_device_foundation.sql',
    ).readAsStringSync();

    expect(sql, contains('set_master_device_locked'));
    expect(sql, contains('revoke_master_device'));
    expect(sql, contains("'master_device_lock'"));
    expect(sql, contains("'master_device_unlock'"));
    expect(sql, contains("'master_device_revoke'"));
    expect(sql, contains('master_admin_audit_log'));
  });
}

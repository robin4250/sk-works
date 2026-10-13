import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Master device status fails closed and bootstrap is first-device only', () {
    final sql = File(
      'supabase/migrations/20260930070500_add_master_strict_device_gate.sql',
    ).readAsStringSync();

    expect(sql, contains('current_master_device_status'));
    expect(sql, contains('bootstrap_first_master_device'));
    expect(sql, contains('public.is_current_user_master_admin()'));
    expect(sql, contains("'can_bootstrap', v_active_count = 0"));
    expect(sql, contains('trusted device approval required'));
    expect(sql, contains("and not d.is_locked"));
    expect(sql, contains('revoked_at is null'));
    expect(sql, isNot(contains('delete from private.master_devices')));
  });
}

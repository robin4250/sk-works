import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('high-use user flow RLS caches auth uid without widening access', () {
    final sql = File(
      'supabase/migrations/20260922033000_cache_auth_uid_in_user_flows.sql',
    ).readAsStringSync();

    expect(sql, contains('users can mark own notifications read'));
    expect(sql, contains('worker or attendance manager can read attendance entries'));
    expect(sql, contains('company members can read daily reports'));
    expect(sql, contains('worker or authorized manager can read payroll statements'));
    expect(sql, contains('users can insert own profile'));
    expect(sql, contains('users can read own profile'));
    expect(sql, contains('users can update own profile'));

    expect(sql, contains('(select auth.uid())'));
    expect(sql, contains('can_manage_attendance'));
    expect(sql, contains('can_manage_payroll'));

    expect(sql, isNot(contains('drop policy')));
    expect(sql, isNot(contains('grant ')));
    expect(sql, isNot(contains('revoke ')));
  });
}

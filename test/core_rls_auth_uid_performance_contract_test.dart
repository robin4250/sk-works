import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('core RLS caches auth uid without changing role scope', () {
    final sql = File(
      'supabase/migrations/20260922031000_cache_auth_uid_in_core_rls.sql',
    ).readAsStringSync();

    expect(sql, contains('user_id = (select auth.uid())'));
    expect(sql, contains("cm.role::text in ('owner','admin','manager')"));
    expect(sql, contains('company_members_self_read'));
    expect(sql, contains('company members can read sites'));
    expect(sql, contains('managers can manage sites'));
    expect(sql, contains('company members can read workers'));
    expect(sql, isNot(contains('grant ')));
    expect(sql, isNot(contains('revoke ')));
  });
}

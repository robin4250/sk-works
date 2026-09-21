import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reference and document RLS caches auth uid without widening access', () {
    final sql = File(
      'supabase/migrations/20260922035000_cache_auth_uid_in_reference_rls.sql',
    ).readAsStringSync();

    for (final policy in [
      'company members can read company document template versions',
      'owners and admins can manage company document template versions',
      'company members can read company document templates',
      'owners and admins can manage company document templates',
      'company members can read daily report workers',
      'company members can read document requirements',
      'owners and admins can manage document requirements',
      'company members can read partner companies',
      'company members can read qualification master',
      'owners and admins can manage qualification master',
      'company members can read qualification aliases',
      'owners and admins can manage qualification aliases',
      'worker or people manager can read worker qualifications',
    ]) {
      expect(sql, contains(policy));
    }

    expect(sql, contains('(select auth.uid())'));
    expect(sql, contains("cm.role::text in ('owner','admin')"));
    expect(sql, contains('can_manage_people'));
    expect(sql, isNot(contains('drop policy')));
    expect(sql, isNot(contains('grant ')));
    expect(sql, isNot(contains('revoke ')));
  });
}

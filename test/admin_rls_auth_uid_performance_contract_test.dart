import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('admin and settings RLS caches auth uid without widening access', () {
    final sql = File(
      'supabase/migrations/20260922043000_cache_auth_uid_in_admin_rls.sql',
    ).readAsStringSync();

    for (final policy in [
      'company members can read company',
      'owners and admins can delete company',
      'owners and admins can update company',
      'company managers can read feature permissions',
      'owners and admins can manage feature permissions',
      'company members can read module settings',
      'owners and admins can insert module settings',
      'owners and admins can update module settings',
      'owners and admins can read line binding audit',
      'owners and admins can read line binding claims',
      'company members can create non-direct communication groups',
      'company members can read attendance verification settings',
    ]) {
      expect(sql, contains(policy));
    }

    expect(sql, contains('(select auth.uid())'));
    expect(sql, contains("cm.role::text in ('owner','admin')"));
    expect(sql, isNot(contains('drop policy')));
    expect(sql, isNot(contains('grant ')));
    expect(sql, isNot(contains('revoke ')));
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('people contact fields are only loaded through guarded RPC', () {
    final repo =
        File('lib/features/people/people_cloud_repository.dart')
            .readAsStringSync();
    final migration = File(
      'supabase/migrations/20260920221500_restrict_people_contact_columns.sql',
    ).readAsStringSync();

    expect(repo, contains("rpc('people_management_records')"));
    expect(repo, isNot(contains("select('id, affiliation, partner_company_id, name, phone, email")));
    expect(migration, contains("not private.has_company_feature(v_company_id, 'can_manage_people')"));
    expect(migration, contains('revoke select on table public.workers'));
    expect(migration, contains('revoke select on table public.partner_companies'));
  });
}

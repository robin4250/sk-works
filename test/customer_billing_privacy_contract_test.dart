import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('site directory exposes customer name without customer billing details', () {
    final repo =
        File('lib/features/sites/site_cloud_repository.dart')
            .readAsStringSync();
    final migration = File(
      'supabase/migrations/20260920222500_restrict_customer_billing_details.sql',
    ).readAsStringSync();

    expect(repo, contains("rpc('site_directory_rows')"));
    expect(repo, isNot(contains('customers(name)')));
    expect(migration, contains("private.has_company_feature(company_id, 'can_view_invoices')"));
    expect(migration, contains("private.has_company_feature(company_id, 'can_manage_invoices')"));
    expect(migration, contains('customer_name text'));
  });
}

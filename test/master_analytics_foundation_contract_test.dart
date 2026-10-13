import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('master analytics collects growth metrics behind master authorization', () {
    final sql = File(
      'supabase/migrations/20260930022000_add_master_analytics_foundation.sql',
    ).readAsStringSync();

    for (final metric in <String>[
      'companies',
      'users',
      'connections',
      'companies_last_7_days',
      'companies_last_30_days',
      'users_last_7_days',
      'users_last_30_days',
      'members_per_company_average',
      'members_per_company_min',
      'members_per_company_max',
    ]) {
      expect(sql, contains(metric));
    }
    expect(sql, contains('public.is_current_user_master_admin()'));
    expect(sql, contains('revoke all on private.master_usage_events'));
  });

  test('analytics foundation documents excluded private content', () {
    final sql = File(
      'supabase/migrations/20260930022000_add_master_analytics_foundation.sql',
    ).readAsStringSync();

    expect(sql, contains('No message bodies'));
    expect(sql, contains('photos'));
    expect(sql, contains('file contents'));
    expect(sql, contains('passwords'));
    expect(sql, contains('OTPs'));
  });
}

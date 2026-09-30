import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Master usage rates are aggregate company percentages', () {
    final sql = File(
      'supabase/migrations/20261001012000_extend_master_usage_rate_kpis.sql',
    ).readAsStringSync();
    final page = File(
      'lib/features/settings/master_operations_dashboard_page.dart',
    ).readAsStringSync();

    expect(sql, contains("'usage_rate_7_percent'"));
    expect(sql, contains("'usage_rate_30_percent'"));
    expect(sql, contains('a.active_companies_7::numeric / r.companies_total::numeric'));
    expect(sql, contains('a.active_companies_30::numeric / r.companies_total::numeric'));
    expect(sql, contains('public.is_current_user_master_admin()'));
    expect(sql, contains('from public, anon'));

    expect(page, contains("'利用率 7日 %'"));
    expect(page, contains("'利用率 30日 %'"));

    for (final forbidden in <String>[
      "'company_id',",
      "'company_name'",
      "'user_id',",
      "'phone'",
      "'email'",
    ]) {
      expect(sql, isNot(contains(forbidden)));
    }
  });
}

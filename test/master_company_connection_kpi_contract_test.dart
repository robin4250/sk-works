import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Master company connection KPIs stay aggregate-only', () {
    final sql = File(
      'supabase/migrations/20260930121500_extend_master_company_connection_kpis.sql',
    ).readAsStringSync();
    final page = File(
      'lib/features/settings/master_operations_dashboard_page.dart',
    ).readAsStringSync();

    for (final metric in <String>[
      'connections',
      'connected_companies',
      'unconnected_companies',
      'connection_rate_percent',
    ]) {
      expect(sql, contains(metric));
    }

    expect(sql, contains('count(distinct company_id)'));
    expect(sql, contains('public.is_current_user_master_admin()'));
    expect(sql, contains('from public, anon'));

    expect(page, contains("'会社間連携'"));
    expect(page, contains("'接続レコード'"));
    expect(page, contains("'連携済み会社'"));
    expect(page, contains("'未連携会社'"));
    expect(page, contains("'連携率 %'"));

    for (final forbidden in <String>[
      'contact_name',
      'phone',
      'email',
      'address',
      'notes',
    ]) {
      expect(sql, isNot(contains(forbidden)));
      expect(page, isNot(contains(forbidden)));
    }
  });
}

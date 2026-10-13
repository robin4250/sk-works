import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Master activity snapshot exposes aggregate retention and velocity only', () {
    final sql = File(
      'supabase/migrations/20260930123000_add_master_activity_retention_snapshot.sql',
    ).readAsStringSync();
    final repository = File(
      'lib/features/settings/master_operations_dashboard_repository.dart',
    ).readAsStringSync();
    final page = File(
      'lib/features/settings/master_operations_dashboard_page.dart',
    ).readAsStringSync();

    for (final metric in <String>[
      'active_companies_7',
      'active_companies_30',
      'retained_companies_30',
      'retention_rate_30_percent',
      'usage_growth_7_percent',
      'registration_growth_7_percent',
    ]) {
      expect(sql, contains(metric));
    }

    expect(sql, contains('public.is_current_user_master_admin()'));
    expect(sql, contains('from public, anon'));
    expect(repository, contains("'get_master_activity_snapshot'"));
    expect(repository, contains("'activity'"));
    expect(page, contains("'利用継続・成長'"));
    expect(page, contains("'アクティブ会社 7日'"));
    expect(page, contains("'30日継続率 %'"));
    expect(page, contains("'利用成長 7日 %'"));
    expect(page, contains("'登録成長 7日 %'"));

    for (final forbidden in <String>[
      'chat_messages',
      'phone',
      'email',
      'latitude',
      'longitude',
      'file_path',
    ]) {
      expect(sql, isNot(contains(forbidden)));
      expect(page, isNot(contains(forbidden)));
    }
  });
}

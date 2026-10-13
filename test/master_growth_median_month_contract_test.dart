import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Master growth extension adds monthly and median aggregate metrics', () {
    final sql = File(
      'supabase/migrations/20260930100000_extend_master_growth_snapshot.sql',
    ).readAsStringSync();
    final page = File(
      'lib/features/settings/master_operations_dashboard_page.dart',
    ).readAsStringSync();

    for (final metric in <String>[
      'companies_current_month',
      'users_current_month',
      'members_per_company_median',
      'percentile_cont(0.5)',
    ]) {
      expect(sql, contains(metric));
    }
    expect(sql, contains('public.is_current_user_master_admin()'));
    expect(sql, contains('from public, anon'));
    expect(page, contains("'新規登録'"));
    expect(page, contains("'1社あたり利用者'"));
    expect(page, contains("'中央値'"));
    expect(page, contains("'会社 今月'"));
    expect(page, contains("'利用者 今月'"));
  });

  test('Master growth extension remains aggregate only', () {
    final sql = File(
      'supabase/migrations/20260930100000_extend_master_growth_snapshot.sql',
    ).readAsStringSync();

    expect(sql, contains('No private content is returned'));
    expect(sql, isNot(contains('chat_messages')));
    expect(sql, isNot(contains('storage.objects')));
    expect(sql, isNot(contains('workers.phone')));
  });
}

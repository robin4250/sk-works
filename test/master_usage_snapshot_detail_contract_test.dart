import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Master usage snapshot exposes aggregate reach and prior-window trends', () {
    final sql = File(
      'supabase/migrations/20260930120000_extend_master_usage_snapshot_detail.sql',
    ).readAsStringSync();

    expect(sql, contains("'events_per_company'"));
    expect(sql, contains("'events_per_user'"));
    expect(sql, contains("'previous_events_total'"));
    expect(sql, contains("'events_change_percent'"));
    expect(sql, contains("'companies_change_percent'"));
    expect(sql, contains("'users_change_percent'"));
    expect(sql, contains("'company_count'"));
    expect(sql, contains("'user_count'"));
    expect(sql, contains('public.is_current_user_master_admin()'));
    expect(sql, contains('revoke all on function public.get_master_usage_snapshot(integer)'));
    expect(sql, contains('from public, anon'));

    for (final forbidden in <String>[
      'email',
      'phone',
      'latitude',
      'longitude',
      'message',
      'file_path',
      'document_path',
    ]) {
      expect(sql, isNot(contains(forbidden)));
    }
  });
}

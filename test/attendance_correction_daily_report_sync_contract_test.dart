import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('approved attendance correction syncs worker-level daily report fields', () {
    final sql = File(
      'supabase/migrations/20261003170400_sync_attendance_corrections_to_daily_report_workers.sql',
    ).readAsStringSync();
    expect(sql, contains('source_report_id'));
    expect(sql, contains('update public.daily_report_workers'));
    expect(sql, contains('overtime_hours'));
    expect(sql, contains('early_hours'));
    expect(sql, contains('night_hours'));
    expect(sql, contains('allowance_amount'));
    expect(sql, isNot(contains('update public.daily_reports\n        set site_id')));
  });
}

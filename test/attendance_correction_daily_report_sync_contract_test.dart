import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('approved attendance correction syncs worker-level daily report fields', () {
    final sql = File(
      'supabase/migrations/20261003170035_sync_attendance_corrections_to_daily_report_workers.sql',
    ).readAsStringSync();
    expect(sql, contains('source_report_id'));
    expect(sql, contains('update public.daily_report_workers'));
    expect(sql, contains('overtime_hours'));
    expect(sql, contains('early_hours'));
    expect(sql, contains('night_hours'));
    expect(sql, contains('allowance_amount'));
    expect(sql, isNot(contains('update public.daily_reports\n        set site_id')));
  });

  test('latest correction migration preserves work category and cancels overlapping leave', () {
    final sql = File(
      'supabase/migrations/20261006103927_fix_attendance_correction_paid_leave_work_category.sql',
    ).readAsStringSync();
    expect(sql, contains("work_category=coalesce(nullif(v_item.proposed_snapshot->>'workCategory',''),work_category,'day')"));
    expect(sql, contains("status='cancelled'"));
    expect(sql, contains('勤務修正承認により有給を取消'));
  });
}

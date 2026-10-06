import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('attendance corrections resync paid leave payroll and invoice drafts', () {
    final repository =
        read('lib/features/attendance/attendance_correction_repository.dart');
    final correction = read(
      'supabase/migrations/20261006103927_fix_attendance_correction_paid_leave_work_category.sql',
    );
    final payroll = read(
      'supabase/migrations/20261006104144_sync_payroll_attendance_detail.sql',
    );
    final invoice = read(
      'supabase/migrations/20261006104325_preserve_invoice_auto_refresh.sql',
    );

    // Proposed correction snapshots carry all values that affect payroll/invoice.
    for (final key in [
      'workCategory',
      'manDays',
      'overtimeHours',
      'earlyHours',
      'nightHours',
      'allowanceNames',
    ]) {
      expect(repository, contains("'$key'"));
    }

    // Approval applies corrected attendance and removes overlapping leave.
    expect(correction, contains('update public.attendance_entries'));
    expect(correction, contains("work_category=coalesce"));
    expect(correction, contains("status='cancelled'"));
    expect(correction, contains('勤務修正承認により有給を取消'));
    expect(correction, contains('update public.daily_report_workers'));

    // Attendance/leave mutations must immediately refresh draft payroll detail.
    expect(payroll, contains('attendance_sync_payroll_detail'));
    expect(payroll, contains('paid_leave_sync_payroll_detail'));
    expect(payroll, contains('after insert or update or delete'));
    for (final label in ['出勤日数', '有給日数', '残業時間', '早出時間', '夜間時間']) {
      expect(payroll, contains("'$label'"));
    }

    // Automatic invoice refresh remains automatic when attendance recalculates.
    expect(invoice, contains("set_config('sko.invoice_auto_refresh','1',true)"));
    expect(invoice, contains('invoice_manual_override_guard'));
    expect(invoice, contains('automatic_calculation'));
    expect(invoice, contains('early_hour_rate_yen'));
    expect(invoice, contains('overtime_hour_rate_yen'));
  });
}

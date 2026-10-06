import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('attendance weekly view opens on today and restores footer after child pages', () {
    final page = read('lib/features/attendance/worker_attendance_sheet_page.dart');

    expect(page, contains('_weekIndexContaining(_month, initial)'));
    expect(page, contains('SkoScrollChromeController.visible.value = true'));
    expect(page, contains('DailyReportPage('));
    expect(page, contains('BulkAttendanceCorrectionPage()'));
    expect(page, contains('PaidLeavePage()'));
  });

  test('attendance correction notifications open the requested approval directly', () {
    final notifications = read('lib/features/notifications/notifications_page.dart');
    final approvals =
        read('lib/features/attendance/attendance_correction_approvals_page.dart');

    expect(notifications, contains("'attendance_correction_request'"));
    expect(notifications, contains('initialRequestId: item.actionId'));
    expect(approvals, contains('this.initialRequestId'));
    expect(approvals, contains('_openedInitialRequest'));
    expect(approvals, contains('_openRequest(item)'));
  });

  test('attendance correction carries work category and resolves paid leave overlap', () {
    final repository =
        read('lib/features/attendance/attendance_correction_repository.dart');
    final migration = read(
      'supabase/migrations/20261006103927_fix_attendance_correction_paid_leave_work_category.sql',
    );

    expect(repository, contains('workCategory'));
    expect(repository, contains("'work_category'"));
    expect(migration, contains("work_category=coalesce"));
    expect(migration, contains("status='cancelled'"));
    expect(migration, contains('勤務修正承認により有給を取消'));
  });

  test('payroll PDF shows corrected attendance metrics', () {
    final pdf = read('lib/features/payroll/payroll_pdf_service.dart');
    final migration = read(
      'supabase/migrations/20261006104144_sync_payroll_attendance_detail.sql',
    );

    for (final label in ['出勤日数', '有給日数', '残業時間', '早出時間', '夜間時間']) {
      expect(pdf, contains("'$label'"));
      expect(migration, contains("'$label'"));
    }
  });

  test('invoice refresh carries early rate and preserves automatic mode', () {
    final early = read(
      'supabase/migrations/20261006104118_fix_invoice_early_rate_refresh.sql',
    );
    final auto = read(
      'supabase/migrations/20261006104325_preserve_invoice_auto_refresh.sql',
    );

    expect(early, contains('early_hour_rate_yen'));
    expect(auto, contains("'sko.invoice_auto_refresh'"));
    expect(auto, contains('invoice_manual_override_guard'));
  });
}

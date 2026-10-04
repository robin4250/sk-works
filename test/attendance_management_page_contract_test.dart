import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('attendance management page supports individual and bulk direct operations', () {
    final page = File('lib/features/attendance/attendance_management_page.dart').readAsStringSync();
    expect(page, contains("text: SkoLanguageController.tr('個別')"));
    expect(page, contains("text: SkoLanguageController.tr('一括')"));
    expect(page, contains("'登録・編集を直接反映'"));
    expect(page, contains("'一括登録・編集を直接反映'"));
    expect(page, contains("'選択範囲を一括削除'"));
    expect(page, contains("'日報・作業内容'"));
    expect(page, contains("ButtonSegment(value: 'paid_leave'"));
    expect(page, contains("ButtonSegment(value: 'off'"));
  });

  test('attendance management is management-only and uses force RPC', () {
    final app = File('lib/app_v2.dart').readAsStringSync();
    final repo = File('lib/features/attendance/attendance_management_repository.dart').readAsStringSync();
    expect(app, contains("key: 'attendance_management'"));
    expect(app, contains("_identity.isManagement && _identity.can('can_manage_attendance')"));
    expect(app, contains("page = const AttendanceManagementPage()"));
    expect(repo, contains("rpc('force_manage_attendance'"));
    expect(repo, contains("const {'owner', 'admin', 'manager'}"));
  });

  test('force management migration keeps attendance leave and reports consistent', () {
    final sql = File('supabase/migrations/20261004093435_add_force_attendance_management.sql').readAsStringSync();
    expect(sql, contains("p_action not in ('upsert','delete')"));
    expect(sql, contains("v_mode not in ('work','paid_leave','off')"));
    expect(sql, contains('attendance_entries'));
    expect(sql, contains('attendance_verifications'));
    expect(sql, contains('paid_leave_requests'));
    expect(sql, contains('daily_reports'));
    expect(sql, contains('daily_report_workers'));
    expect(sql, contains("v_role not in ('owner','admin','manager')"));
  });
}

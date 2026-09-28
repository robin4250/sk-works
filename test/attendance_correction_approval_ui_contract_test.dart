import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('configured approvers can open pending attendance corrections', () {
    final page = read('lib/features/attendance/attendance_cloud_page.dart');
    final repository =
        read('lib/features/attendance/attendance_cloud_repository.dart');

    expect(page, contains('過去勤怠の修正承認'));
    expect(page, contains('_canApproveAttendanceCorrections'));
    expect(repository, contains('canApproveAttendanceCorrections'));
    expect(repository, contains("'can_approve_daily_report_edits'"));
  });

  test('attendance correction approval page shows before and after changes', () {
    final page =
        read('lib/features/attendance/attendance_correction_approvals_page.dart');
    final repository = read(
      'lib/features/attendance/attendance_correction_approval_repository.dart',
    );

    expect(page, contains('承認して反映'));
    expect(page, contains('却下'));
    expect(page, contains('_SnapshotDiff'));
    expect(page, contains('おまとめサイン'));
    expect(repository, contains('pending_attendance_correction_rows'));
    expect(repository, contains('attendance_correction_item_rows'));
    expect(repository, contains('decide_attendance_correction_request'));
  });
}

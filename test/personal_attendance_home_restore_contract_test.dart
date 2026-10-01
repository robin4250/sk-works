import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('personal attendance card restores selected method site and active button state', () {
    final app = File('lib/app_v2.dart').readAsStringSync();
    final home =
        File('lib/features/home/friendly_home_content.dart').readAsStringSync();
    final status =
        File('lib/features/home/personal_attendance_status_repository.dart')
            .readAsStringSync();
    final verification =
        File('lib/features/attendance/attendance_verification_page.dart')
            .readAsStringSync();
    final verificationRepository =
        File('lib/features/attendance/attendance_verification_repository.dart')
            .readAsStringSync();

    expect(home, contains("'本日の勤務報告'"));
    expect(home, contains("'選択中の出勤方法'"));
    expect(home, contains("'選択中の現場'"));
    expect(home, contains("'出勤方法と現場を選択'"));
    expect(home, contains("onOpen('attendance_select')"));
    expect(home, contains("status.shouldHighlightClockIn"));
    expect(home, contains("status.shouldHighlightClockOut"));
    expect(home, contains('AnimationController('));
    expect(home, contains('..repeat(reverse: true)'));
    expect(home, contains('FadeTransition('));
    expect(home, contains('Icons.notifications_active_outlined'));
    expect(home, isNot(contains('if (requiredDocumentAttention.hasMissing)')));

    expect(status, contains("PersonalAttendanceState.notClockedIn"));
    expect(status, contains("PersonalAttendanceState.working"));
    expect(status, contains("PersonalAttendanceState.clockedOut"));
    expect(status, contains("attendance_verification_settings"));
    expect(status, contains("attendance_verifications"));
    expect(status, contains(".eq('company_id', companyId)"));
    expect(status, contains(".eq('worker_id', id)"));

    expect(
      verificationRepository,
      contains("'sko_attendance_site_\${companyId}_\${user.id}'"),
    );
    expect(verification, contains('loadPreferredSiteId()'));
    expect(verification, contains('savePreferredSiteId(value)'));

    expect(app, contains("if (key == 'attendance_select')"));
    expect(app, contains('const AttendanceQuickSelectionPage()'));
    expect(app, contains('_loadPersonalAttendanceStatus()'));
  });
}

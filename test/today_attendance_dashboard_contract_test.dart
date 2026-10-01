import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('today attendance restores self and subcontractor tabs from existing data', () {
    final page =
        File('lib/features/attendance/today_attendance_page.dart').readAsStringSync();
    final repository =
        File('lib/features/attendance/today_attendance_repository.dart').readAsStringSync();
    final app = File('lib/app_v2.dart').readAsStringSync();

    expect(repository, contains("'partner_company'"));
    expect(repository, contains('partner_companies!workers_partner_company_id_fkey(name)'));
    expect(repository, contains('attendance_verifications'));
    expect(repository, contains("eventType == 'clock_in'"));
    expect(repository, contains("eventType == 'clock_out'"));

    expect(page, contains("'本日の出勤'"));
    expect(page, contains("'自社 "));
    expect(page, contains("'下請け "));
    expect(page, contains("'合計'"));
    expect(page, contains("'出勤中'"));
    expect(page, contains("'退勤済'"));

    expect(app, contains("import 'features/attendance/today_attendance_page.dart';"));
    expect(app, contains('builder: (_) => const TodayAttendancePage()'));
  });
}

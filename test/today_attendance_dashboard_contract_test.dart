import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('today attendance groups self and subcontractors from existing worker affiliation', () {
    final page =
        File('lib/features/attendance/today_attendance_page.dart').readAsStringSync();
    final repository =
        File('lib/features/attendance/today_attendance_repository.dart').readAsStringSync();
    final app = File('lib/app_v2.dart').readAsStringSync();

    expect(repository, contains("'partner_company'"));
    expect(repository, contains('partner_companies!workers_partner_company_id_fkey(name)'));
    expect(repository, contains('workers!attendance_verifications_worker_id_fkey'));
    expect(repository, contains('sites!attendance_verifications_site_id_fkey'));
    expect(repository, contains('attendance_verifications'));
    expect(repository, contains("event_type == 'clock_in'"));
    expect(repository, contains("event_type == 'clock_out'"));

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

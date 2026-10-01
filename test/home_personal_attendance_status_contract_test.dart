import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('home personal attendance card shows selected method site and state-driven buttons', () {
    final app = File('lib/app_v2.dart').readAsStringSync();
    final home =
        File('lib/features/home/friendly_home_content.dart').readAsStringSync();

    expect(app, contains('WorkerAttendanceSheetRepository.maybeCreate()'));
    expect(app, contains('AttendanceVerificationRepository.maybeCreate()'));
    expect(app, contains('PersonalAttendanceState.working'));
    expect(app, contains('PersonalAttendanceState.finished'));
    expect(app, contains("'location_photo' => '位置情報＋写真'"));
    expect(app, contains("'location' => '位置情報'"));
    expect(app, contains("'manual' => '手動'"));

    expect(home, contains("'本日の勤務報告'"));
    expect(home, contains("'選択中の出勤方法'"));
    expect(home, contains("'選択中の現場'"));
    expect(home, contains("'出勤方法と現場を選択'"));
    expect(home, contains("onOpen('attendance_verify')"));
    expect(home, contains('final clockInActive = state != PersonalAttendanceState.working'));
    expect(home, contains('final clockOutActive = state == PersonalAttendanceState.working'));
    expect(home, contains("label: '出勤'"));
    expect(home, contains("label: '退勤'"));
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all roles keep personal clock in/out while management stays permissioned', () {
    final source =
        File('lib/features/home/friendly_home_content.dart').readAsStringSync();

    expect(source, contains("'本日の勤怠報告'"));
    expect(source, contains("onOpen('clock_in')"));
    expect(source, contains("onOpen('clock_out')"));
    expect(source, contains("onOpen('workplace_select')"));
    expect(source, contains("onOpen('attendance_method_vehicle')"));
    expect(source, contains("'選択中の出勤方法："));
    expect(source, contains("'選択中の現場："));

    expect(source, isNot(contains("identity.can('can_manage_attendance')")));
    expect(source, contains("visibleHomeKeys.contains('attendance_today')"));
    expect(source, contains('_TodayAttendanceHomeCard'));
    expect(source, contains('出勤状況を確認'));
  });
}

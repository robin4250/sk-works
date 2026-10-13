import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('home attendance card uses current verification state without new schema', () {
    final repository = File(
      'lib/features/attendance/attendance_verification_repository.dart',
    ).readAsStringSync();
    final home =
        File('lib/features/home/friendly_home_content.dart').readAsStringSync();
    final app = File('lib/app_v2.dart').readAsStringSync();

    expect(repository, contains('class HomeAttendanceStatus'));
    expect(repository, contains("from('attendance_verification_settings')"));
    expect(repository, contains("from('attendance_verifications')"));
    expect(repository, contains("rpc('ensure_current_user_worker')"));
    expect(repository, contains("sites(name)"));
    expect(repository, contains("'clock_in'"));
    expect(repository, contains("'clock_out'"));

    expect(home, contains("'本日の勤怠報告'"));
    expect(home, contains("'選択中の出勤方法："));
    expect(home, contains("'選択中の現場："));
    expect(home, contains("'現場の選択（1現場／複数現場）'"));
    expect(home, contains("'出勤方法と車両を選択'"));
    expect(home, contains("onOpen('workplace_select')"));
    expect(home, contains("onOpen('attendance_method_vehicle')"));
    expect(home, contains('HomeAttendancePhase.working'));
    expect(home, contains('HomeAttendancePhase.finished'));

    expect(app, contains('AttendanceVerificationRepository.maybeCreate()'));
    expect(app, contains('_loadHomeAttendanceStatus()'));
    expect(app, contains('attendanceStatus: _homeAttendanceStatus'));
  });
}

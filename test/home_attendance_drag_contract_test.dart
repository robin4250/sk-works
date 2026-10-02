import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('attendance home cards keep full size while joining drag order', () {
    final home = File(
      'lib/features/home/friendly_home_content.dart',
    ).readAsStringSync();
    final app = File('lib/app_v2.dart').readAsStringSync();

    expect(home, contains("keyName: 'attendance_verify'"));
    expect(home, contains("keyName: 'attendance_today'"));
    expect(home, contains('_DraggableHomeCard('));
    expect(home, contains('LongPressDraggable<String>'));
    expect(home, contains('DragTarget<String>'));
    expect(home, contains('_PersonalAttendanceCard('));
    expect(home, contains('_TodayAttendanceHomeCard('));

    // Keep both cards outside the compact grid so their existing full-width
    // card sizing is preserved while their order remains draggable.
    final attendanceVerify = home.indexOf("keyName: 'attendance_verify'");
    final attendanceToday = home.indexOf("keyName: 'attendance_today'");
    final gridClass = home.indexOf('class _ActionGrid');
    expect(attendanceVerify, greaterThanOrEqualTo(0));
    expect(attendanceToday, greaterThanOrEqualTo(0));
    expect(attendanceVerify, lessThan(gridClass));
    expect(attendanceToday, lessThan(gridClass));

    expect(app, contains('onReorderAction: _reorderHomeActionByKey'));
    expect(app, contains("prefs.setStringList('sko_home_action_order'"));
    expect(app, contains("key: 'attendance_verify'"));
    expect(app, contains("key: 'attendance_today'"));
  });
}

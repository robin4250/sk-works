import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('today attendance supports English display', () {
    final source =
        File('lib/features/attendance/today_attendance_page.dart').readAsStringSync();

    expect(source, contains("SkoLanguageController.isEnglish ? \"Today's Attendance\""));
    expect(source, contains("'My Company"));
    expect(source, contains("'Subcontractors"));
    expect(source, contains("'Past Month'"));
    expect(source, contains("'No attendance records for today yet.'"));
    expect(source, contains("'Working'"));
    expect(source, contains("'Clocked Out'"));
    expect(source, contains("'Retry'"));
  });
}

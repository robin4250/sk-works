import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('attendance calendars distinguish Saturdays and Sundays', () {
    final page = File(
      'lib/features/attendance/worker_attendance_sheet_page.dart',
    ).readAsStringSync();

    final weekLabel = File(
      'lib/features/attendance/attendance_week_date_label.dart',
    ).readAsStringSync();
    expect(weekLabel, contains('DateTime.sunday'));
    expect(weekLabel, contains('DateTime.saturday'));
    expect(weekLabel, contains('Colors.blue.shade700'));
    expect(page, contains('DateTime.sunday'));
    expect(page, contains('DateTime.saturday'));
    expect(page, contains('Colors.blue.shade700'));
  });
}

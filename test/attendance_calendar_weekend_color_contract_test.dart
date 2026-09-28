import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('attendance calendars distinguish Saturdays and Sundays', () {
    final page = File(
      'lib/features/attendance/worker_attendance_sheet_page.dart',
    ).readAsStringSync();

    expect(page, contains("weekday == '日'"));
    expect(page, contains("weekday == '土'"));
    expect(page, contains('DateTime.sunday'));
    expect(page, contains('DateTime.saturday'));
    expect(page, contains('Colors.blue.shade700'));
  });
}

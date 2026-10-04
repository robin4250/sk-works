import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('勤務修正 exposes retrospective 休み→有給 flow', () {
    final correction = File(
      'lib/features/attendance/bulk_attendance_correction_page.dart',
    ).readAsStringSync();
    final leave = File(
      'lib/features/attendance/paid_leave_correction_page.dart',
    ).readAsStringSync();
    expect(correction, contains("'勤務修正'"));
    expect(correction, contains("'休み→有給'"));
    expect(leave, contains('submitRetrospective'));
    expect(leave, contains('!date.isAfter(todayDate)'));
  });
}

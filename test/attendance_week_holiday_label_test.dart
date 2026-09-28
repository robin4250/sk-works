import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/japan_holiday.dart';

void main() {
  test('JapanHoliday returns 2026 national holiday names', () {
    expect(JapanHoliday.name(DateTime(2026, 1, 1)), '元日');
    expect(JapanHoliday.name(DateTime(2026, 2, 23)), '天皇誕生日');
    expect(JapanHoliday.name(DateTime(2026, 9, 21)), '敬老の日');
    expect(JapanHoliday.name(DateTime(2026, 9, 22)), '国民の休日');
    expect(JapanHoliday.name(DateTime(2026, 9, 23)), '秋分の日');
  });

  test('weekly attendance shows holiday name in small red text', () {
    final page = File(
      'lib/features/attendance/worker_attendance_sheet_page.dart',
    ).readAsStringSync();

    expect(page, contains('JapanHoliday.name(date)'));
    expect(page, contains('if (holidayName != null)'));
    expect(page, contains('fontSize: 9'));
    expect(page, contains('color: colors.error'));
    expect(page, contains('isHoliday || date.weekday == DateTime.sunday'));
  });
}

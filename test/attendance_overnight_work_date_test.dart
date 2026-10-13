import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/attendance_work_date.dart';

void main() {
  test('next-day end belongs to linked work date across month and year', () {
    expect(attendanceEventWorkDate(DateTime(2027, 1, 1, 5),
        {'report_date': '2026-12-31'}), DateTime(2026, 12, 31));
    expect(attendanceEventWorkDate(DateTime(2026, 11, 1, 5),
        {'report_date': '2026-10-31'}), DateTime(2026, 10, 31));
  });
  test('ordinary and unlinked events retain their date', () {
    final time = DateTime(2026, 10, 8, 17);
    for (final report in [null, {}, {'report_date': 'invalid'},
      {'report_date': '2026-10-08'}]) {
      expect(attendanceEventWorkDate(time, report), DateTime(2026, 10, 8));
    }
  });
}

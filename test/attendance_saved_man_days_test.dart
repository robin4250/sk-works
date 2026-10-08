import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/attendance_work_date.dart';
import 'package:sk_works/features/attendance/worker_attendance_sheet_repository.dart';

void main() {
  test('saved positive attendance wins without a visible site or clock event', () {
    expect(attendanceDayHasWorkedData(manDays: 0.5), isTrue);
    expect(attendanceDayHasWorkedData(manDays: 0), isFalse);
    final day = WorkerAttendanceDay(date: DateTime(2026, 10, 8), manDays: 0.5);
    expect(day.worked, isTrue);
  });

  test('positive saved hours count as work even with zero base and no join', () {
    final date = DateTime(2026, 10, 8);
    for (final day in [
      WorkerAttendanceDay(date: date, overtimeHours: 1),
      WorkerAttendanceDay(date: date, earlyHours: 0.5),
      WorkerAttendanceDay(date: date, nightHours: 2),
    ]) {
      expect(day.worked, isTrue);
      expect(day.manDays, 0);
    }
    expect(WorkerAttendanceDay(date: date).worked, isFalse);
    expect(attendanceDayHasWorkedData(manDays: 0, overtimeHours: 1), isTrue);
    expect(attendanceDayHasWorkedData(manDays: 0, earlyHours: 1), isTrue);
    expect(attendanceDayHasWorkedData(manDays: 0, nightHours: 1), isTrue);
  });

  test('calendar days, holiday dates and man-days remain separate units', () {
    final first = DateTime(2026, 10, 8);
    final second = DateTime(2026, 10, 9);
    final month = WorkerAttendanceMonth(year: 2026, month: 10, days: {
      first: WorkerAttendanceDay(date: first, manDays: 2, hasHolidayWork: true),
      second: WorkerAttendanceDay(date: second, manDays: 0.5),
    });
    expect(month.workedDays, 2);
    expect(month.manDays, 2.5);
    expect(month.holidayWorkedDays, 1);
    expect(month.paidLeaveDays, 0);
  });

  test('legacy event-only attendance and approved leave remain recognizable', () {
    final first = DateTime(2026, 10, 8);
    final second = DateTime(2026, 10, 9);
    final month = WorkerAttendanceMonth(year: 2026, month: 10, days: {
      first: WorkerAttendanceDay(date: first, clockIn: first),
      second: WorkerAttendanceDay(date: second, paidLeave: true),
    });
    expect(month.workedDays, 1);
    expect(month.manDays, 0);
    expect(month.paidLeaveDays, 1);
    expect(month.holidayWorkedDays, 0);
  });
}

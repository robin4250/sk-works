import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/shifts/shift_attendance_status.dart';

void main() {
  final start = DateTime.utc(2026, 10, 26, 13);
  final end = DateTime.utc(2026, 10, 26, 22);
  ShiftAttendanceStatus status({DateTime? input, DateTime? output,
      bool confirmed = true, bool holiday = false, bool readComplete = true, DateTime? now}) =>
    compareConfirmedShift(planConfirmed: confirmed, attendanceReadComplete: readComplete, plannedHoliday: holiday,
      scheduledStart: start, scheduledEnd: end, now: now ?? end,
      lateGrace: const Duration(minutes: 5), earlyGrace: const Duration(minutes: 5),
      absenceDecisionTime: end, checkLate: true, checkEarlyLeave: true,
      checkAbsence: true, confirmedClockIn: input, linkedConfirmedClockOut: output);

  test('absence is pending until explicit decision time', () {
    expect(status(now: start).pending, isTrue);
    expect(status().flags, contains(ShiftAttendanceFlag.absent));
  });
  test('failed or partial event read cannot assert absence or a late arrival', () {
    final missing = status(readComplete: false);
    expect(missing.pending, isTrue);
    expect(missing.flags, isEmpty);
    final partial = status(readComplete: false, input: start.add(const Duration(minutes: 6)));
    expect(partial.pending, isTrue);
    expect(partial.flags, isEmpty);
  });
  test('overnight shift uses actual end and grace boundaries', () {
    final result = status(input: start.add(const Duration(minutes: 6)),
      output: end.subtract(const Duration(minutes: 6)));
    expect(result.flags, {ShiftAttendanceFlag.late, ShiftAttendanceFlag.earlyLeave});
    expect(result.pending, isFalse);
    expect(status(input: start.add(const Duration(minutes: 5)), output: end).flags, isEmpty);
  });
  test('holiday, unconfirmed plan and unlinked checkout cannot assert attendance', () {
    expect(status(holiday: true).pending, isTrue);
    expect(status(confirmed: false).flags, isEmpty);
    expect(status(output: end).flags, isEmpty);
  });
  test('open shift retains observed late but is pending', () {
    final result = status(input: start.add(const Duration(minutes: 6)));
    expect(result.pending, isTrue);
    expect(result.flags, contains(ShiftAttendanceFlag.late));
  });
}

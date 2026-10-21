import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/attendance_checkout_minute_guard.dart';

void main() {
  test('seconds and fractional seconds do not make a different minute', () {
    final start = DateTime.parse('2026-10-21T08:15:00+09:00');
    expect(isSameAttendanceMinute(start, start), isTrue);
    expect(isSameAttendanceMinute(start,
        DateTime.parse('2026-10-21T08:15:59.999999+09:00')), isTrue);
  });
  test('next minute and next calendar date are allowed', () {
    final start = DateTime.parse('2026-10-21T08:15:59.999999+09:00');
    expect(isSameAttendanceMinute(start,
        DateTime.parse('2026-10-21T08:16:00+09:00')), isFalse);
    expect(isSameAttendanceMinute(start,
        DateTime.parse('2026-10-22T08:15:59.999999+09:00')), isFalse);
    expect(isSameAttendanceMinute(DateTime.parse('2026-12-31T23:59:59+09:00'),
        DateTime.parse('2027-01-01T00:00:00+09:00')), isFalse);
  });
  test('offset representations compare the actual minute', () {
    expect(isSameAttendanceMinute(DateTime.parse('2026-10-21T08:15:01+09:00'),
        DateTime.parse('2026-10-20T23:15:59Z')), isTrue);
    expect(isSameAttendanceMinute(DateTime.parse('2026-10-21T08:15:01+09:00'),
        DateTime.parse('2026-10-21T08:15:01Z')), isFalse);
  });
  test('only the specific rejection is converted to the requested message', () {
    expect(isSameMinuteCheckoutError(StateError(sameMinuteCheckoutMessage)), isTrue);
    expect(isSameMinuteCheckoutError(StateError('connection lost')), isFalse);
    expect(sameMinuteCheckoutMessage,
        '出勤と同じ時刻のため退勤できません。時刻が進んでから再度お試しください');
  });
}

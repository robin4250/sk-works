const sameMinuteCheckoutMessage =
    '出勤と同じ時刻のため退勤できません。時刻が進んでから再度お試しください';

/// Compare actual instants at minute precision, including the calendar date.
/// UTC avoids a device timezone changing the result. Japan has no DST and its
/// offset is a whole number of minutes, so this equals the server JST rule.
bool isSameAttendanceMinute(DateTime clockIn, DateTime clockOut) {
  final start = clockIn.toUtc();
  final end = clockOut.toUtc();
  return start.year == end.year && start.month == end.month &&
      start.day == end.day && start.hour == end.hour && start.minute == end.minute;
}

bool isSameMinuteCheckoutError(Object error) =>
    error.toString().contains(sameMinuteCheckoutMessage);

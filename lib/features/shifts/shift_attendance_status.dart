/// Read-only comparison of a confirmed plan with server-confirmed events.
/// Unknown information stays unknown; this function never records attendance.
enum ShiftAttendanceFlag { late, earlyLeave, absent }

class ShiftAttendanceStatus {
  const ShiftAttendanceStatus({required this.pending, required this.flags});
  final bool pending;
  final Set<ShiftAttendanceFlag> flags;
}

ShiftAttendanceStatus compareConfirmedShift({
  required bool planConfirmed,
  // True only after a complete, authorized server read of the relevant events.
  // A failed or partial read must never turn a missing clock-in into absence.
  required bool attendanceReadComplete,
  required bool plannedHoliday,
  required DateTime scheduledStart,
  required DateTime scheduledEnd,
  required DateTime now,
  required Duration lateGrace,
  required Duration earlyGrace,
  required DateTime absenceDecisionTime,
  required bool checkLate,
  required bool checkEarlyLeave,
  required bool checkAbsence,
  DateTime? confirmedClockIn,
  DateTime? linkedConfirmedClockOut,
}) {
  final invalid = !planConfirmed || !attendanceReadComplete || plannedHoliday ||
      !scheduledEnd.isAfter(scheduledStart) ||
      lateGrace.isNegative || earlyGrace.isNegative ||
      absenceDecisionTime.isBefore(scheduledStart) ||
      (confirmedClockIn != null && confirmedClockIn.isAfter(now)) ||
      (linkedConfirmedClockOut != null && (confirmedClockIn == null ||
        linkedConfirmedClockOut.isBefore(confirmedClockIn) || linkedConfirmedClockOut.isAfter(now)));
  if (invalid) {
    return const ShiftAttendanceStatus(pending: true, flags: {});
  }
  final flags = <ShiftAttendanceFlag>{};
  if (confirmedClockIn == null) {
    if (checkAbsence && !now.isBefore(absenceDecisionTime)) {
      flags.add(ShiftAttendanceFlag.absent);
      return ShiftAttendanceStatus(pending: false, flags: Set.unmodifiable(flags));
    }
    return const ShiftAttendanceStatus(pending: true, flags: {});
  }
  if (checkLate && confirmedClockIn.isAfter(scheduledStart.add(lateGrace))) {
    flags.add(ShiftAttendanceFlag.late);
  }
  if (linkedConfirmedClockOut != null && checkEarlyLeave &&
      linkedConfirmedClockOut.isBefore(scheduledEnd.subtract(earlyGrace))) {
    flags.add(ShiftAttendanceFlag.earlyLeave);
  }
  return ShiftAttendanceStatus(pending: linkedConfirmedClockOut == null,
      flags: Set.unmodifiable(flags));
}

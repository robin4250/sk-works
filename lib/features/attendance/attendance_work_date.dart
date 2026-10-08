/// Linked reports or a server-validated shift own the work date.
/// Unlinked legacy events keep their civil date; they are not silently repaired.
DateTime attendanceEventWorkDate(DateTime confirmed, Object? report, {Object? workDate}) {
  final raw = report is Map ? report['report_date'] : null;
  final date = raw is String ? DateTime.tryParse(raw) : null;
  final shiftDate = workDate is String ? DateTime.tryParse(workDate) : null;
  final source = shiftDate ?? date ?? confirmed;
  return DateTime(source.year, source.month, source.day);
}

/// A positive saved attendance amount is evidence even without a readable site join.
bool attendanceDayHasWorkedData({
  required double manDays,
  double overtimeHours = 0,
  double earlyHours = 0,
  double nightHours = 0,
  String? siteName,
  DateTime? clockIn,
  DateTime? clockOut,
}) => manDays > 0 || overtimeHours > 0 || earlyHours > 0 || nightHours > 0 ||
    (siteName?.trim().isNotEmpty ?? false) ||
    clockIn != null || clockOut != null;

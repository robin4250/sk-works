/// Linked report dates own overnight events; unlinked events keep their civil date.
DateTime attendanceEventWorkDate(DateTime confirmed, Object? report) {
  final raw = report is Map ? report['report_date'] : null;
  final date = raw is String ? DateTime.tryParse(raw) : null;
  final source = date ?? confirmed;
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

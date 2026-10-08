/// Linked report dates own overnight events; unlinked events keep their civil date.
DateTime attendanceEventWorkDate(DateTime confirmed, Object? report) {
  final raw = report is Map ? report['report_date'] : null;
  final date = raw is String ? DateTime.tryParse(raw) : null;
  final source = date ?? confirmed;
  return DateTime(source.year, source.month, source.day);
}

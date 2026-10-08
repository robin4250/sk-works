import '../attendance/attendance_work_date.dart';

/// Match the first start used by daily_report_clocked_in_destinations.
/// Canonical evidence owns vehicle/route, including an explicit null vehicle.
/// Legacy starts retain the pre-migration selection fallback.
Map<String, dynamic>? dailyReportClockInSnapshot(
  Iterable<Map<String, dynamic>> rows, {
  required String workerId,
  required DateTime workDate,
  String? siteId,
  String? routeId,
}) {
  final day = DateTime(workDate.year, workDate.month, workDate.day);
  final candidates = rows.where((row) {
    final confirmed = DateTime.tryParse(row['confirmed_at']?.toString() ?? '');
    return confirmed != null && row['event_type'] == 'clock_in' &&
        row['worker_id']?.toString() == workerId &&
        row['site_id']?.toString() == siteId &&
        row['route_assignment_id']?.toString() == routeId &&
        attendanceEventWorkDate(confirmed.toLocal(), null, workDate: row['work_date']) == day;
  }).toList()
    ..sort((a, b) => DateTime.parse(a['confirmed_at'].toString())
        .compareTo(DateTime.parse(b['confirmed_at'].toString())));
  if (candidates.isEmpty || candidates.first['work_date'] == null) {
    return null;
  }
  return candidates.first;
}

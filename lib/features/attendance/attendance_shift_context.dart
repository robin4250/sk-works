import 'attendance_work_date.dart';

/// One explicit start record. Confirmation timestamps remain actual timestamps.
class AttendanceShiftContext {
  const AttendanceShiftContext({
    required this.id,
    required this.workerId,
    required this.workDate,
    required this.clockIn,
    required this.verificationMode,
    this.siteId,
    this.routeId,
    this.vehicleId,
    this.siteName,
    this.routeName,
    this.vehicleName,
  });

  final String id;
  final String workerId;
  final DateTime workDate;
  final DateTime clockIn;
  final String verificationMode;
  final String? siteId;
  final String? routeId;
  final String? vehicleId;
  final String? siteName;
  final String? routeName;
  final String? vehicleName;

  static AttendanceShiftContext? fromRow(Map<String, dynamic> row) {
    final confirmed = DateTime.tryParse(row['confirmed_at']?.toString() ?? '')?.toLocal();
    final id = row['id']?.toString() ?? '';
    final workerId = row['worker_id']?.toString() ?? '';
    if (row['event_type'] != 'clock_in' || confirmed == null || id.isEmpty || workerId.isEmpty) return null;
    String? joinedName(String key, String field) {
      final join = row[key];
      return join is Map ? join[field]?.toString() : null;
    }
    return AttendanceShiftContext(
      id: id,
      workerId: workerId,
      workDate: attendanceEventWorkDate(confirmed, row['daily_reports'], workDate: row['work_date']),
      clockIn: confirmed,
      verificationMode: row['verification_mode']?.toString() ?? 'manual',
      siteId: row['site_id']?.toString(),
      routeId: row['route_assignment_id']?.toString(),
      vehicleId: row['vehicle_id']?.toString(),
      siteName: joinedName('sites', 'name'),
      routeName: joinedName('route_assignments', 'route_name'),
      vehicleName: joinedName('vehicles', 'display_name'),
    );
  }
}

/// Eligible starts in the requested window; never assigns an old end to a start.
/// An unlinked legacy end makes preceding starts unsuitable for automatic use.
/// Multiple remaining starts are returned for an explicit user choice.
List<AttendanceShiftContext> openAttendanceShifts(
  Iterable<Map<String, dynamic>> rows, {
  required String workerId,
  required DateTime now,
}) {
  final previousDay = DateTime(now.year, now.month, now.day - 1);
  final relevant = rows.where((row) => row['worker_id']?.toString() == workerId).toList();
  final closedIds = <String>{};
  DateTime? legacyEnd;
  for (final row in relevant) {
    final time = DateTime.tryParse(row['confirmed_at']?.toString() ?? '')?.toLocal();
    if (time == null || time.isAfter(now) || row['event_type'] != 'clock_out') continue;
    final source = row['source_clock_in_id']?.toString();
    if (source != null && source.isNotEmpty) {
      closedIds.add(source);
    } else if (legacyEnd == null || time.isAfter(legacyEnd)) {
      legacyEnd = time;
    }
  }
  final starts = <String, AttendanceShiftContext>{};
  for (final row in relevant) {
    final start = AttendanceShiftContext.fromRow(row);
    if (start == null || closedIds.contains(start.id) || start.clockIn.isAfter(now) ||
        start.clockIn.isBefore(previousDay) ||
        (legacyEnd != null && !start.clockIn.isAfter(legacyEnd))) continue;
    starts[start.id] = start;
  }
  return starts.values.toList()..sort((a, b) => a.clockIn.compareTo(b.clockIn));
}

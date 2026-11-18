import 'dart:typed_data';

import '../attendance/worker_attendance_sheet_repository.dart';
import '../attendance/worker_attendance_registered_allowances.dart';
import 'retirement_pdf_renderer.dart';

Future<Uint8List> renderRetirementEnvelope(
  Map envelope,
  RetirementPdfRenderer renderer,
) async {
    final source = Map<String, Object?>.from(envelope['snapshot'] as Map);
    final Uint8List pdf;
    switch (envelope['kind']) {
      case 'own_payroll':
        pdf = await renderer.payroll(source,
          verifiedPersonId: envelope['ownerId'] as String,
          snapshotPersonId: envelope['ownerId'] as String,
          companyId: envelope['companyId'] as String);
      case 'own_attendance':
        if (source['complete'] != true ||
            source['companyId'] != envelope['companyId'] ||
            source['workerId'] != envelope['workerId']) {
          throw const FormatException('Invalid attendance scope.');
        }
        final month = DateTime.parse(source['periodStart'] as String);
        final WorkerAttendanceMonth attendance;
        if (source['attendanceRows'] case final List _) {
          List<Map<String,dynamic>> rows(String key) =>
              List<Map<String,dynamic>>.from(
                (source[key] as List).map((row) => Map<String,dynamic>.from(row as Map)));
          final entries = rows('attendanceRows');
          final workerId = source['workerId'] as String;
          attendance = WorkerAttendanceSheetRepository.projectMonth(month,
            attendanceRows: entries,
            registered: workerAttendanceRegisteredAllowances(
              rows('signedReports'), workerId:workerId,
              reportIds: entries.map((row)=>row['source_report_id']).whereType<String>().toSet(),
            ),
            verificationRows:rows('verificationRows'),
            allApprovedLeaveRows:rows('approvedLeave'),
            grantedDays:(source['grantedDays'] as num).toDouble(),
            rawUnits:source['allowanceUnits'],
          );
        } else {
          final days = <DateTime, WorkerAttendanceDay>{};
          for (final row in source['days'] as List) {
            final day = _day(row as Map);
            if (days.containsKey(day.date)) {
              throw const FormatException('Duplicate attendance date.');
            }
            days[day.date] = day;
          }
          attendance = WorkerAttendanceMonth(year:month.year,month:month.month,days:days);
        }
        pdf = await renderer.attendance(
          attendance,
          cutoff: DateTime.parse(envelope['cutoff'] as String),
          workerName: source['workerName'] as String,
        );
      default:
        throw const FormatException('Invalid retirement document type.');
    }
    return pdf;
}

WorkerAttendanceDay _day(Map source) {
  DateTime? timestamp(String key) => source[key] == null
    ? null : DateTime.parse(source[key] as String);
  double number(String key) => (source[key] as num).toDouble();
  return WorkerAttendanceDay(
    date: DateTime.parse(source['date'] as String),
    siteName: source['siteName'] as String?,
    clockIn: timestamp('clockIn'),
    clockOut: timestamp('clockOut'),
    overtimeHours: number('overtimeHours'),
    earlyHours: number('earlyHours'),
    nightHours: number('nightHours'),
    manDays: number('manDays'),
    hasHolidayWork: source['hasHolidayWork'] as bool,
    allowanceYen: source['allowanceYen'] as int,
    allowanceNames: List<String>.from(source['allowanceNames'] as List),
    allowanceUnits: Map<String, String>.from(source['allowanceUnits'] as Map),
    paidLeave: source['paidLeave'] as bool,
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/attendance_pending_report_details.dart';
import 'package:sk_works/features/attendance/worker_attendance_sheet_repository.dart';
import 'package:sk_works/features/attendance/worker_attendance_sheet_page.dart';

void main() {
  final date = DateTime(2026, 10, 26);
  final data = WorkerAttendanceMonth(year: 2026, month: 10, days: {
    date: WorkerAttendanceDay(date: date, siteName: '検証現場', manDays: 1,
      overtimeHours: 2.5, earlyHours: 0.5, nightHours: 1,
      allowanceNames: const ['鉄骨手当', '交通手当', '追加手当'],
      pendingReports: [AttendancePendingReportDetails(reportId: 'draft', date: date,
        siteName: '未確定現場', overtimeHours: 3, earlyHours: 0, nightHours: 0,
        allowanceNames: const ['未確定手当'], selections: const [])]),
  });
  testWidgets('weekly details wrap instead of hiding allowances offscreen', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: attendanceWeekForTesting(
      month: date, week: [for (var i = 0; i < 7; i++) date.add(Duration(days: i))], data: data))));
    expect(find.text('残業2.5時間'), findsOneWidget);
    expect(find.text('早出0.5時間'), findsOneWidget);
    expect(find.text('追加手当1回'), findsOneWidget);
    expect(find.textContaining('日報未確定・未確定現場・残業3h・未確定手当'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('calendar displays saved overtime early hours and pending details separately', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: attendanceCalendarForTesting(month: date, data: data)))));
    expect(find.text('残業2.5h 早出0.5h 夜間1h'), findsOneWidget);
    expect(find.textContaining('日報未確定・残業3h・未確定手当'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(data.overtimeHours, 2.5);
    expect(data.allowanceCounts, isNot(contains('未確定手当')));
  });
  test('draft binding rejects other workers, dates, finalized and duplicate rows', () {
    Map<String, Object?> row() => {'report_id': 'r', 'worker_id': 'w',
      'overtime_hours': 1, 'early_hours': 0, 'night_hours': 0,
      'daily_reports': {'id': 'r', 'report_date': '2026-10-26', 'status': 'draft'}};
    expect(AttendancePendingReportDetails.parse([row()], workerId: 'w', month: date).single.overtimeHours, 1);
    for (final rows in [
      [row()..['worker_id'] = 'other'], [row(), row()],
      [row()..['daily_reports'] = {'id': 'r', 'report_date': '2026-11-01', 'status': 'draft'}],
      [row()..['daily_reports'] = {'id': 'r', 'report_date': '2026-10-26', 'status': 'signed'}],
      [row()..['overtime_hours'] = -1],
    ]) {
      expect(() => AttendancePendingReportDetails.parse(rows, workerId: 'w', month: date), throwsFormatException);
    }
  });
}

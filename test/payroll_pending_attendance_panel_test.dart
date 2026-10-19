import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/attendance_management_repository.dart';
import 'package:sk_works/features/attendance/attendance_management_page.dart';
import 'package:sk_works/features/payroll/payroll_pending_attendance_panel.dart';
import 'attendance_unrecorded_punches_test.dart' as existing;

class PanelFixture extends existing.PageFixture {
  PanelFixture(super.client);
  bool pending = true;
  int reads = 0;
  @override
  Future<PayrollPendingAttendance?> loadPayrollPendingDays(String statementId) async {
    reads++;
    return PayrollPendingAttendance(workerId: existing.actor,
      dates: pending ? [DateTime(2026,10,13)] : []);
  }
}

void main() {
  testWidgets('payroll date opens the existing editor with exact employee and date, no automatic quantity', (tester) async {
    final f = existing.Fixture(); await f.start(); addTearDown(f.client.dispose);
    final repository = PanelFixture(f.client);
    final loaded = <(String,DateTime)>[];
    repository.onLoad = (worker,date) async {
      loaded.add((worker,date));
      return AttendanceManagementCell(mode: 'pending_work', date: date, workerId: worker,
        manDays: 0, hasUnrecordedPunches: true);
    };
    var returned = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child:
      PayrollPendingAttendancePanel(statementId: 'statement', repository: repository,
        onReturn: () async {returned++;})))));
    await tester.pumpAndSettle();
    expect(find.text('未確定の勤務 1日'), findsOneWidget);
    await tester.tap(find.text('未確定の勤務 1日')); await tester.pumpAndSettle();
    await tester.tap(find.text('10/13 勤務を確認')); await tester.pumpAndSettle();
    expect(loaded, [(existing.actor,DateTime(2026,10,13))]);
    expect(find.text('未確定'), findsOneWidget);
    expect(repository.reads, greaterThanOrEqualTo(2));
    repository.pending = false;
    await tester.pageBack(); await tester.pumpAndSettle();
    expect(returned, 1);
    expect(find.text('未確定の勤務 1日'), findsNothing);
    expect(f.calls, isEmpty);
  });
  testWidgets('invisible initial employee is refused instead of silently selecting the first employee', (tester) async {
    final f = existing.Fixture(); await f.start(); addTearDown(f.client.dispose);
    final repository = PanelFixture(f.client);
    var loaded = false;
    repository.onLoad = (worker,date) async {
      loaded = true; return AttendanceManagementCell(mode:'off',date:date,workerId:worker);
    };
    await tester.pumpWidget(MaterialApp(home: AttendanceManagementPage(repository:repository,
      initialWorkerId:'invisible-worker',initialDate:DateTime(2026,10,13))));
    await tester.pumpAndSettle();
    expect(find.text('対象の従業員を勤怠管理で確認できません。'), findsOneWidget);
    expect(loaded, isFalse);
  });
}

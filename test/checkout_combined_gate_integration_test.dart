import 'package:sk_works/features/auth/secondary_protected_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/checkout_report_gate.dart';
import 'package:sk_works/features/attendance/attendance_management_page.dart';
import 'package:sk_works/features/attendance/attendance_management_repository.dart';
import 'package:sk_works/features/notifications/notification_bell.dart';
import 'package:sk_works/features/attendance/checkout_report_gate_repository.dart';
import 'package:sk_works/features/attendance/scheduled_checkout_gate.dart';
import 'package:sk_works/features/attendance/scheduled_checkout_repository.dart';
import 'package:sk_works/features/daily_reports/shared_daily_report_repository.dart';

const _actor = '00000000-0000-0000-0000-000000000010';
PendingCheckoutRegistration _report({bool conflict = false}) => PendingCheckoutRegistration(
  companyId: 'company', workerId: 'worker', workDate: DateTime(2026, 10, 25),
  sourceClockInId: 'source', clockOutId: 'out', siteId: 'site',
  state: conflict ? 'source_conflict' : 'reporter_signature_missing',
  blocking: true, scopeFingerprint: 'report-scope');

class _Reports implements CheckoutReportGateRepository {
  List<PendingCheckoutRegistration> pending = [];
  @override String? get actorId => _actor;
  @override Future<List<PendingCheckoutRegistration>> readPending() async => pending;
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _ManagementContext implements SharedDailyReportContext {
  _ManagementContext(this.canManageAttendance, {this.isManagementHold = false});
  @override final bool canManageAttendance;
  @override final bool isManagementHold;
  @override String get managementHoldMessage => '手入力済み勤怠・給与との差異を勤怠管理で確認してください。';
  @override String get actorId => _actor;
  @override String get companyId => 'company';
  @override String? get workerId => 'worker';
  @override DateTime get workDate => DateTime(2026, 10, 25);
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _SharedReports implements SharedDailyReportRepository {
  _SharedReports(this.canManage, {this.hold = false});
  final bool canManage;
  final bool hold;
  @override Future<SharedDailyReportContext> loadForSource(String sourceClockInId) async =>
      _ManagementContext(canManage, isManagementHold: hold);
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ManagementRepository implements AttendanceManagementRepository {
  final reads = <({String workerId, DateTime date})>[];
  @override
  Future<({List<AttendanceManagementOption> workers, List<AttendanceManagementOption> sites})> loadOptions() async => (
    workers: const [AttendanceManagementOption(id: 'worker', name: '対象従業員')],
    sites: const <AttendanceManagementOption>[]);
  @override
  Future<AttendanceManagementCell> loadCell({required String workerId, required DateTime date}) async {
    reads.add((workerId: workerId, date: date));
    return AttendanceManagementCell(mode: 'off', date: date, workerId: workerId);
  }
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final restricted in [false, true]) {
    testWidgets('real management page keeps target while restricting notification escape $restricted', (tester) async {
      final repository = _ManagementRepository();
      final date = DateTime(2026, 10, 25);
      await tester.pumpWidget(MaterialApp(home: AttendanceManagementPage(
        repository: repository, initialWorkerId: 'worker', initialDate: date,
        restrictedRecovery: restricted)));
      await tester.pumpAndSettle();
      expect(find.byType(SkoNotificationBell), restricted ? findsNothing : findsOneWidget);
      expect(repository.reads, [(workerId: 'worker', date: date)]);
      expect(find.text('2026/10/25'), findsOneWidget);
      expect(find.text('対象従業員'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('report recovery authenticates before restricted management and returns to the block', (tester) async {
    final reports = _Reports()..pending = [_report(conflict: true)];
    final controller = CheckoutReportGateController()..activate(_actor, () async {});
    await tester.pumpWidget(CheckoutReportBackBoundary(controller: controller,
      child: MaterialApp(builder: (_, child) => CheckoutReportGate(
        controller: controller, repository: reports,
        sharedReportRepository: _SharedReports(true), child: child!),
        home: const Scaffold(body: Text('ordinary-home')))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('管理者の勤怠管理で確認'));
    await tester.pumpAndSettle();
    final protected = tester.widget<SecondaryProtectedPage>(find.byType(SecondaryProtectedPage));
    final page = protected.child as AttendanceManagementPage;
    expect(find.byType(AttendanceManagementPage), findsNothing);
    expect(find.textContaining('ログイン状態を確認できません'), findsOneWidget);
    expect(page.restrictedRecovery, isTrue);
    expect(page.initialWorkerId, 'worker');
    expect(page.initialDate, DateTime(2026, 10, 25));
    expect(find.byType(SkoNotificationBell), findsNothing);
    expect(find.text('ordinary-home'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AttendanceManagementPage), findsNothing);
    expect(find.text('管理者の勤怠管理で確認'), findsOneWidget);
    expect(find.text('ordinary-home'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  ScheduledCheckoutState schedule(bool due) => ScheduledCheckoutState(
    actorId: _actor, enabled: true, serverTime: DateTime.utc(2026, 10, 25, 8),
    targets: due ? [ScheduledCheckoutTarget(companyId: 'company', workerId: 'worker',
      sourceId: 'source', siteId: 'site', workDate: '2026-10-25',
      reminderAt: DateTime.utc(2026, 10, 25, 7), due: true,
      scopeFingerprint: 'clock-scope', canManageAttendance: false)] : []);

  testWidgets('report gate wins over scheduled confirmation, then real checkout hands back to report gate', (tester) async {
    final reports = _Reports()..pending = [_report()];
    final controller = CheckoutReportGateController()..activate(_actor, () async {});
    var due = true;
    final ordinary = GlobalKey<NavigatorState>();
    await tester.pumpWidget(CheckoutReportBackBoundary(controller: controller,
      child: MaterialApp(navigatorKey: ordinary,
        builder: (_, child) => CheckoutReportGate(controller: controller, repository: reports,
          reportBuilder: (_, saved) => Scaffold(body: TextButton(onPressed: saved,
            child: const Text('pending-report'))),
          scheduledFlowBuilder: (actor, normal) => ScheduledCheckoutGate(actorId: actor,
            load: () async => schedule(due), postpone: (_) async => schedule(false),
            checkoutBuilder: (context, target) => Scaffold(body: TextButton(onPressed: () {
              due = false;
              reports.pending = [_report()];
              controller.requestCheck();
              Navigator.of(context).pop();
            }, child: const Text('save-exact-checkout'))), child: normal),
          child: child!), home: const Scaffold(body: Text('ordinary-home')))));
    await tester.pumpAndSettle();
    expect(find.text('pending-report'), findsOneWidget);
    expect(find.text('退勤予定時刻です。'), findsNothing);
    reports.pending = [];
    controller.requestCheck();
    await tester.pumpAndSettle();
    expect(find.text('退勤予定時刻です。'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('ordinary-home'), findsNothing);
    ordinary.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('ordinary-deep-link'))));
    await tester.pumpAndSettle();
    expect(find.text('ordinary-deep-link'), findsNothing);
    await tester.tap(find.text('退勤して日報へ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('save-exact-checkout'));
    await tester.pumpAndSettle();
    expect(find.text('pending-report'), findsOneWidget);
    expect(find.text('ordinary-deep-link'), findsNothing);
    reports.pending = [];
    controller.requestCheck();
    await tester.pumpAndSettle();
    expect(find.text('ordinary-deep-link'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final allowed in [false, true]) {
    testWidgets('conflicted source exposes scoped management only when server allows $allowed', (tester) async {
      final reports = _Reports()..pending = [_report(conflict: true)];
      final controller = CheckoutReportGateController()..activate(_actor, () async {});
      await tester.pumpWidget(CheckoutReportBackBoundary(controller: controller,
        child: MaterialApp(builder: (_, child) => CheckoutReportGate(
          controller: controller, repository: reports,
          sharedReportRepository: _SharedReports(allowed),
          managementBuilder: (_) => const Scaffold(body: Text('authorized-management')),
          child: child!), home: const Scaffold(body: Text('ordinary-home')))));
      await tester.pumpAndSettle();
      expect(find.text('ordinary-home'), findsNothing);
      expect(find.text('管理者の勤怠管理で確認'), allowed ? findsOneWidget : findsNothing);
      if (allowed) {
        await tester.tap(find.text('管理者の勤怠管理で確認'));
        await tester.pumpAndSettle();
        expect(find.text('authorized-management'), findsOneWidget);
        expect(find.text('ordinary-home'), findsNothing);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('authorized-management'), findsNothing);
        expect(find.text('管理者の勤怠管理で確認'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
  for (final allowed in [false, true]) {
    testWidgets('financial hold is persistent and offers only server-authorized management $allowed', (tester) async {
      final reports = _Reports()..pending = [_report()];
      final controller = CheckoutReportGateController()..activate(_actor, () async {});
      await tester.pumpWidget(CheckoutReportBackBoundary(controller: controller,
        child: MaterialApp(builder: (_, child) => CheckoutReportGate(
          controller: controller, repository: reports,
          sharedReportRepository: _SharedReports(allowed, hold: true),
          managementBuilder: (_) => const Scaffold(body: Text('authorized-management')),
          reportBuilder: (_, __) => const Scaffold(body: Text('must-not-edit-report')),
          child: child!), home: const Scaffold(body: Text('ordinary-home')))));
      await tester.pumpAndSettle();
      expect(find.textContaining('手入力済み勤怠・給与との差異'), findsOneWidget);
      expect(find.text('再試行'), findsNothing);
      expect(find.text('must-not-edit-report'), findsNothing);
      expect(find.text('ordinary-home'), findsNothing);
      expect(find.text('管理者の勤怠管理で確認'), allowed ? findsOneWidget : findsNothing);
      if (allowed) {
        await tester.tap(find.text('管理者の勤怠管理で確認'));
        await tester.pumpAndSettle();
        expect(find.text('authorized-management'), findsOneWidget);
        expect(find.text('ordinary-home'), findsNothing);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

}

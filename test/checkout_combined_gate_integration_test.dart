import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/checkout_report_gate.dart';
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
  _ManagementContext(this.canManageAttendance);
  @override final bool canManageAttendance;
  @override String get actorId => _actor;
  @override String get companyId => 'company';
  @override String? get workerId => 'worker';
  @override DateTime get workDate => DateTime(2026, 10, 25);
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _SharedReports implements SharedDailyReportRepository {
  _SharedReports(this.canManage);
  final bool canManage;
  @override Future<SharedDailyReportContext> loadForSource(String sourceClockInId) async =>
      _ManagementContext(canManage);
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
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
}

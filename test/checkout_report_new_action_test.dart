import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/checkout_report_gate_repository.dart';
import 'package:sk_works/features/attendance/checkout_report_resume_repository.dart';
import 'package:sk_works/features/attendance/checkout_report_new_action.dart';

PendingCheckoutRegistration pending(String source) => PendingCheckoutRegistration(
  companyId: 'company', workerId: 'worker', workDate: DateTime(2026,10,26),
  sourceClockInId: source, clockOutId: 'out-$source', siteId: 'site-$source',
  state: 'checkout_deferred', blocking: false, scopeFingerprint: 'scope-$source',
  choiceAvailable: true, memberCount: 2);
CheckoutReportResumeTarget target(String source) => CheckoutReportResumeTarget(
  companyId: 'company', workerId: 'worker', workDate: DateTime(2026,10,26),
  sourceClockInId: source, clockOutId: 'out-$source', siteId: 'site-$source',
  sourceClockInIds: [source], clockOutIds: ['out-$source'],
  destinationName: '現場$source', state: CheckoutReportState.missing);
class Gate implements CheckoutReportGateRepository {
  @override String? actorId = 'actor';
  @override bool? choiceEnforcementEnabled = true;
  List<PendingCheckoutRegistration> rows = [pending('A'),pending('B')];
  final List<String> chosen = [];
  @override Future<List<PendingCheckoutRegistration>> readPending() async => rows;
  @override Future<List<PendingCheckoutRegistration>> readCreationSources(DateTime month) async => rows;
  @override Future<bool> isOwnWorker(String workerId) async => workerId == 'worker';
  @override Future<void> choose(PendingCheckoutRegistration value, {required bool createReport}) async {
    if (!createReport) throw StateError('unexpected checkout-only');
    chosen.add(value.sourceClockInId);
  }
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class Resume implements CheckoutReportResumeRepository {
  @override Future<List<CheckoutReportResumeTarget>> loadDay({required String workerId, required DateTime workDate}) async => [target('A'),target('B')];
  @override Future<CheckoutReportResumeTarget> revalidate(CheckoutReportResumeTarget value) async => value;
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
void main() {
  late Gate gate;
  late Resume resume;
  bool? handled;
  final opened = <String>[];
  Future<void> mount(WidgetTester tester, {String? workerId}) async {
    gate = Gate(); resume = Resume(); handled = null; opened.clear();
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () async {
        handled = await offerNewCheckoutReport(context, month: DateTime(2026,10),
          workerId: workerId, gateRepository: gate, resumeRepository: resume,
          opener: (_, value) async => opened.add(value.sourceClockInId));
      }, child: const Text('＋新規日報'))))));
  }
  testWidgets('viewing list and cancelling explicit new never records reporting responsibility', (tester) async {
    await mount(tester); await tester.pumpAndSettle();
    expect(gate.chosen, isEmpty);
    await tester.tap(find.text('＋新規日報')); await tester.pumpAndSettle();
    expect(gate.chosen, isEmpty); expect(opened, isEmpty);
    await tester.tap(find.text('戻る')); await tester.pumpAndSettle();
    expect(handled, true); expect(gate.chosen, isEmpty);
  });
  testWidgets('multiple actual sources require selection and record exactly selected source', (tester) async {
    await mount(tester);
    await tester.tap(find.text('＋新規日報')); await tester.pumpAndSettle();
    expect(gate.chosen, isEmpty);
    await tester.tap(find.byKey(const ValueKey('new-report-source-B'))); await tester.pumpAndSettle();
    expect(gate.chosen, ['B']); expect(opened, ['B']); expect(handled, true);
  });
  testWidgets('enforced flow without actual source cannot fall through to legacy new editor', (tester) async {
    await mount(tester); gate.rows = [];
    await tester.tap(find.text('＋新規日報')); await tester.pumpAndSettle();
    expect(handled, true); expect(opened, isEmpty); expect(gate.chosen, isEmpty);
    expect(find.textContaining('本人の退勤記録がありません'), findsOneWidget);
  });
  testWidgets('OFF flow and another-worker administrative path remain separate', (tester) async {
    await mount(tester); gate.choiceEnforcementEnabled = false;
    await tester.tap(find.text('＋新規日報')); await tester.pumpAndSettle();
    expect(handled, false); expect(gate.chosen, isEmpty);
    await mount(tester, workerId: 'other-worker');
    await tester.tap(find.text('＋新規日報')); await tester.pumpAndSettle();
    expect(handled, false); expect(gate.chosen, isEmpty);
  });
}

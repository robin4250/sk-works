import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/checkout_report_gate.dart';
import 'package:sk_works/features/attendance/checkout_report_gate_repository.dart';

const _actor = '00000000-0000-0000-0000-000000000001';
PendingCheckoutRegistration _pending(String source) => PendingCheckoutRegistration(
  companyId: 'company', workerId: 'worker', workDate: DateTime(2026,10,21),
  sourceClockInId: source, clockOutId: 'out-$source', siteId: 'site',
  state: 'reporter_signature_missing', blocking: true, scopeFingerprint: 'fingerprint');

class _Repository implements CheckoutReportGateRepository {
  @override String? actorId = _actor;
  List<PendingCheckoutRegistration> rows = [_pending('in')];
  Completer<List<PendingCheckoutRegistration>>? next;
  bool fail = false;
  int reads = 0;
  @override Future<List<PendingCheckoutRegistration>> readPending() async {
    reads++;
    if (fail) { throw StateError('fixture read failure'); }
    final pending = next;
    next = null;
    return pending == null ? rows : pending.future;
  }
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Repository repository;
  late CheckoutReportGateController controller;
  setUp(() { repository = _Repository(); controller = CheckoutReportGateController(); });
  late GlobalKey<NavigatorState> normalNavigator;
  Future<void> mount(WidgetTester tester, {
    Future<void> Function(BuildContext, PendingCheckoutRegistration)? beforeRegistration,
  }) async {
    normalNavigator = GlobalKey<NavigatorState>();
    controller.activate(_actor, () async {});
    await tester.pumpWidget(CheckoutReportBackBoundary(controller: controller, child: MaterialApp(navigatorKey: normalNavigator, builder: (_, child) => CheckoutReportGate(
      controller: controller, repository: repository, beforeRegistration: beforeRegistration,
      reportBuilder: (target, saved) => PopScope(canPop: false, child: Scaffold(body: Column(children: [
        Text('report-${target.sourceClockInId}'),
        TextButton(onPressed: saved, child: const Text('server-recheck')),
        Builder(builder: (context) => TextButton(onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('signature-capture')))),
          child: const Text('open-signature'))),
      ]))), child: child!), home: const Scaffold(body: Text('ordinary-home')))));
    await tester.pump();
  }
  testWidgets('dedicated Navigator has an isolated Hero scope while ordinary Navigator stays mounted', (tester) async {
    await mount(tester);
    final scope = tester.widget<HeroControllerScope>(find.ancestor(
      of: find.text('report-in'), matching: find.byType(HeroControllerScope)).first);
    expect(scope.controller, isNull);
    expect(find.byType(Navigator, skipOffstage: false), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
  testWidgets('pending server evidence isolates normal screens and local completion never unlocks', (tester) async {
    await mount(tester);
    expect(find.text('report-in'), findsOneWidget);
    expect(find.text('ordinary-home'), findsNothing);
    await tester.tap(find.text('server-recheck'));
    await tester.pump();
    expect(find.text('report-in'), findsOneWidget);
    expect(find.text('ordinary-home'), findsNothing);
    repository.rows = [];
    await tester.tap(find.text('server-recheck'));
    await tester.pump();
    expect(find.text('ordinary-home'), findsOneWidget);
    expect(repository.reads, 3);
  });
  testWidgets('unknown and read failure remain blocked and retry uses server', (tester) async {
    final pending = Completer<List<PendingCheckoutRegistration>>();
    repository.next = pending;
    await mount(tester);
    expect(find.text('ordinary-home'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.completeError(StateError('fixture unavailable'));
    await tester.pump();
    expect(find.text('ordinary-home'), findsNothing);
    expect(find.text('ログインし直す'), findsOneWidget);
    await tester.tap(find.text('再試行'));
    await tester.pump();
    expect(find.text('report-in'), findsOneWidget);
  });
  testWidgets('back cannot dismiss root report; next pending source gets its own page', (tester) async {
    await mount(tester);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('report-in'), findsOneWidget);
    repository.rows = [_pending('second')];
    await tester.tap(find.text('server-recheck'));
    await tester.pump();
    expect(find.text('report-second'), findsOneWidget);
    expect(find.text('ordinary-home'), findsNothing);
  });
  testWidgets('system back returns from signature to the pending report and root replacement stays hidden', (tester) async {
    await mount(tester);
    await tester.tap(find.text('open-signature'));
    await tester.pumpAndSettle();
    expect(find.text('signature-capture'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('report-in'), findsOneWidget);
    normalNavigator.currentState!.pushReplacement(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('ordinary-deep-link'))));
    await tester.pumpAndSettle();
    expect(find.text('ordinary-deep-link'), findsNothing);
    expect(find.text('report-in'), findsOneWidget);
  });
  testWidgets('actor transition invalidates in-flight response', (tester) async {
    final pending = Completer<List<PendingCheckoutRegistration>>();
    repository.next = pending;
    await mount(tester);
    repository.actorId = 'different';
    controller.activate('different', () async {});
    await tester.pump();
    pending.complete([]);
    await tester.pump();
    expect(find.text('ordinary-home'), findsNothing);
    expect(find.text('report-in'), findsOneWidget);
  });
  testWidgets('group checkout stays inside the restricted flow before reporter registration', (tester) async {
    final sources = <String>[];
    await mount(tester, beforeRegistration: (context, target) async {
      sources.add(target.sourceClockInId);
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (context) =>
        PopScope(canPop: false, child: Scaffold(body: Column(children: [
          const Text('scoped-group-checkout'),
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('group-to-report')),
        ])))));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('scoped-group-checkout'), findsOneWidget);
    expect(find.text('ordinary-home'), findsNothing);
    expect(find.text('report-in'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('scoped-group-checkout'), findsOneWidget);
    normalNavigator.currentState!.pushReplacement(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('ordinary-deep-link'))));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('ordinary-deep-link'), findsNothing);
    await tester.tap(find.text('group-to-report'));
    await tester.pumpAndSettle();
    expect(find.text('report-in'), findsOneWidget);
    expect(find.text('ordinary-deep-link'), findsNothing);
    await tester.tap(find.text('server-recheck'));
    await tester.pump();
    expect(sources, ['in']);
    expect(find.text('report-in'), findsOneWidget);
    repository.rows = [];
    await tester.tap(find.text('server-recheck'));
    await tester.pumpAndSettle();
    expect(find.text('ordinary-deep-link'), findsOneWidget);
  });
}

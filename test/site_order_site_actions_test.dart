import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/sites/site_order_site_actions.dart';
import 'package:sk_works/features/sites/admin_site_financial_page.dart';
import 'package:sk_works/features/sites/admin_site_financial_repository.dart';
import 'package:sk_works/features/sites/site_order_workflow_page.dart';
import 'package:sk_works/features/sites/site_order_outgoing_compose_page.dart';
import 'package:sk_works/features/sites/site_order_workflow_repository.dart';

const site = '70000000-0000-4000-8000-000000000001';
const otherSite = '70000000-0000-4000-8000-000000000002';
const package = '70000000-0000-4000-8000-000000000003';
class _Api extends SiteOrderWorkflowApi {
  bool allowed = false, expired = false, gateError = false, supported = true;
  int admissions = 0, writes = 0;
  final siteReads = <String>[];
  Completer<List<Map<String, dynamic>>>? historyHold;
  @override bool get invalidated => expired || uiRetired;
  @override void requireCurrent() { if (invalidated) throw StateError('retired'); }
  @override Future<void> verify() async => requireCurrent();
  @override Future<bool> canUseWorkflow() async { requireCurrent(); return supported; }
  @override Future<bool> canCreateOutgoing() async {
    requireCurrent(); admissions++;
    if (gateError) throw StateError('unsupported capability');
    return allowed;
  }
  void expire() { expired = true; notifyListeners(); }
  @override Future<List<Map<String, dynamic>>> historyForSite(String id,
      {String? before, String? beforeId}) async {
    requireCurrent(); siteReads.add(id);
    if (historyHold != null) return historyHold!.future;
    return [{ 'package_id': package, 'work_name': '保存された工事',
      'period_start': '2026-10-01', 'period_end': '2026-10-31', 'pdf_sha256': 'a' * 64 }];
  }
  @override Future<Map<String, dynamic>> detail(String id) async {
    requireCurrent();
    return {'package_id': id, 'is_recipient': true, 'can_write': true,
      'approved': false, 'rejected': false, 'body': {'work_name': '保存された工事'},
      'site_projection': {'name': '共有された現場'}};
  }
  @override Future<Map<String, dynamic>> refuse(String id, String request) async {
    writes++; throw StateError('no real writes in fixture');
  }
  @override Future<Uint8List> original(String id, String kind) async =>
      throw StateError('native PDF outside this widget fixture');
  // Any unexpectedly reached mutation/renderer is a test failure, never a stub
  // success. This fixture supplies only the read surfaces exercised below.
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _FinancialRepository implements AdminSiteFinancialRepository {
  @override Future<bool> canManage() async => true;
  @override Future<List<AdminSiteFinancialRecord>> loadAll() async => const [
    AdminSiteFinancialRecord(siteId: site, siteName: '金融設定の対象現場', status: 'active',
      workerDailyRateYen: 0, overtimeHourRateYen: 0, earlyHourRateYen: 0,
      nightHourRateYen: 0, billingUnitPriceYen: 123, billingOvertimeHourRateYen: 0,
      billingEarlyHourRateYen: 0, billingMonthlyRateYen: 0,
      billingSquareMeterUnitPriceYen: 0, billingSquareMeterQuantity: 0,
      billingContractAmountYen: 0, welfareRate: 0),
  ];
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _Input {
  const _Input(this.api, [this.siteId = site, this.name = '対象の現場']);
  final _Api api;
  final String siteId, name;
}
Future<({GlobalKey<NavigatorState> navigator, ValueNotifier<_Input> input,
    List<bool?> results})> _mount(WidgetTester tester, _Api api,
    {TextScaler textScaler = TextScaler.noScaling, String siteId = site}) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  final navigator = GlobalKey<NavigatorState>();
  final input = ValueNotifier(_Input(api, siteId));
  final results = <bool?>[];
  await tester.pumpWidget(MaterialApp(navigatorKey: navigator,
    builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: textScaler), child: child!),
    home: Scaffold(body: Builder(builder: (context) => TextButton(
      onPressed: () async {
        results.add(await Navigator.push<bool>(context, MaterialPageRoute(
          builder: (_) => ValueListenableBuilder<_Input>(valueListenable: input,
            builder: (_, value, __) => SiteOrderSiteActionsPage(
              key: const Key('owned-site'), api: value.api,
              siteId: value.siteId, siteName: value.name)))));
      }, child: const Text('現場を開く'))))));
  await tester.tap(find.text('現場を開く')); await tester.pumpAndSettle();
  addTearDown(input.dispose);
  return (navigator: navigator, input: input, results: results);
}
Future<void> _history(WidgetTester tester) async {
  await tester.tap(find.text('過去の注文書')); await tester.pumpAndSettle();
  expect(find.byType(SiteOrderWorkflowPage), findsOneWidget);
}
void main() {
  testWidgets('missing backend disables all site module actions without a read or write', (tester) async {
    final api = _Api()..supported = false;
    await _mount(tester, api);
    expect(api.siteReads, isEmpty); expect(api.writes, 0);
    for (final label in ['注文書を見る', '管理倉庫（注文書・請書）', '過去の注文書']) {
      final button = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, label));
      expect(button.onPressed, isNull);
    }
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '注文書を作る')).onPressed, isNull);
    await tester.pumpWidget(const SizedBox.shrink()); await tester.pump();
  });
  testWidgets('site warehouse uses exact site and groups saved orders and replies without a write', (tester) async {
    final api = _Api(); await _mount(tester, api);
    await tester.tap(find.text('管理倉庫（注文書・請書）')); await tester.pumpAndSettle();
    expect(find.text('対象の現場の管理倉庫（注文書・請書）'), findsOneWidget);
    expect(find.byType(SiteOrderWorkflowPage), findsOneWidget);
    expect(api.siteReads, [site]);
    expect(api.writes, 0);
  });

  testWidgets('unavailable order API never blocks actual parent financial editor', (tester) async {
    // This is a synthetic existing-permission repository, not a live Auth test.
    await tester.pumpWidget(MaterialApp(home: AdminSiteFinancialPage(
      repository: _FinancialRepository())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('金融設定の対象現場')); await tester.pumpAndSettle();
    expect(find.byType(SiteOrderSiteActionsPage), findsOneWidget);
    expect(find.textContaining('利用状態を確認できません'), findsOneWidget);
    expect(find.text('現場の金額設定'), findsNothing);
    await tester.tap(find.byTooltip('閉じる')); await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('金額設定')); await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('請求書用'), findsOneWidget);
    expect(find.byWidgetPredicate((widget) => widget is TextField &&
      widget.controller?.text == '123'), findsWidgets);
    await tester.tap(find.text('キャンセル')); await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('three order actions never contain a financial callback and OFF never creates', (tester) async {
    final api = _Api(); final host = await _mount(tester, api);
    final hosted = tester.widget<SiteOrderSiteActionsPage>(find.byType(SiteOrderSiteActionsPage)).api as _Api;
    expect(find.text('注文書を見る'), findsOneWidget);
    expect(find.text('注文書を作る'), findsOneWidget);
    expect(find.text('過去の注文書'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '注文書を作る')).onPressed, isNull);
    expect(hosted.writes, 0); expect(api.writes, 0);
    expect(find.text('現場の金額設定'), findsNothing);
    await tester.tap(find.byTooltip('閉じる')); await tester.pumpAndSettle();
    expect(host.results, [null]); expect(hosted.uiRetired, isTrue);
  });
  testWidgets('view selects a saved package without guessing latest, history uses exact UUID', (tester) async {
    final api = _Api(); await _mount(tester, api);
    await tester.tap(find.text('注文書を見る')); await tester.pumpAndSettle();
    expect(find.text('保存された注文書を選択'), findsOneWidget);
    expect(api.siteReads, [site]);
    expect(find.text('保存された工事'), findsOneWidget);
    expect(api.writes, 0);
  });
  testWidgets('creation uses existing compose and exact site only after fresh capability', (tester) async {
    final api = _Api()..allowed = true; await _mount(tester, api);
    await tester.tap(find.text('注文書を作る')); await tester.pumpAndSettle();
    final compose = tester.widget<SiteOrderOutgoingComposePage>(find.byType(SiteOrderOutgoingComposePage));
    expect(compose.siteId, site); expect(identical(compose.api, api), isTrue);
    expect(api.admissions, greaterThanOrEqualTo(3)); expect(api.writes, 0);
  });
  testWidgets('capability failure is visibly unknown and does not create', (tester) async {
    final api = _Api()..gateError = true; await _mount(tester, api);
    expect(find.textContaining('利用状態を確認できません'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '注文書を作る')).onPressed, isNull);
    expect(api.writes, 0);
  });
  for (final change in ['site', 'name', 'api', 'background', 'session']) {
    testWidgets('$change retires all owned children and late reads stay hidden', (tester) async {
      final api = _Api()..historyHold = Completer<List<Map<String, dynamic>>>();
      final host = await _mount(tester, api);
      await tester.tap(find.text('過去の注文書')); await tester.pump();
      if (change == 'site') host.input.value = _Input(api, otherSite);
      if (change == 'name') host.input.value = _Input(api, site, '変更された現場');
      if (change == 'api') host.input.value = _Input(_Api());
      if (change == 'background') tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      if (change == 'session') api.expire();
      await tester.pumpAndSettle();
      api.historyHold!.complete([{'work_name': '遅延した非公開工事'}]);
      await tester.pumpAndSettle();
      expect(find.byType(SiteOrderWorkflowPage), findsNothing);
      expect(find.text('遅延した非公開工事'), findsNothing);
      expect(find.text('対象の現場'), findsNothing);
      expect(api.uiRetired, isTrue); expect(api.writes, 0);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('invalid initial UUID never admits an order route', (tester) async {
    final api = _Api(); await _mount(tester, api, siteId: 'not-a-site');
    expect(api.admissions, 0); expect(api.writes, 0);
    expect(find.text('注文書を見る'), findsNothing);
    expect(api.uiRetired, isTrue);
  });
  testWidgets('capability loss immediately before creation never opens compose', (tester) async {
    final api = _Api()..allowed = true; await _mount(tester, api);
    api.allowed = false;
    await tester.tap(find.text('注文書を作る')); await tester.pumpAndSettle();
    expect(find.byType(SiteOrderOutgoingComposePage), findsNothing);
    expect(api.writes, 0);
  });
  testWidgets('removing the host disposes an owned refusal dialog without sending', (tester) async {
    final api = _Api(); await _mount(tester, api);
    await _history(tester);
    await tester.tap(find.text('保存された工事')); await tester.pumpAndSettle();
    await tester.tap(find.text('注文を辞退')); await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home: Text('外側の画面')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(api.uiRetired, isTrue); expect(api.writes, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets('owned refusal dialog retires without popping unrelated root modal', (tester) async {
    final api = _Api(); final host = await _mount(tester, api);
    final hosted = tester.widget<SiteOrderSiteActionsPage>(find.byType(SiteOrderSiteActionsPage)).api as _Api;
    await _history(tester);
    await tester.tap(find.text('保存された工事')); await tester.pumpAndSettle();
    await tester.tap(find.text('注文を辞退')); await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    unawaited(showDialog<void>(context: host.navigator.currentContext!,
      builder: (_) => const AlertDialog(title: Text('別のルート通知'))));
    await tester.pumpAndSettle();
    hosted.expire(); await tester.pumpAndSettle();
    expect(find.text('別のルート通知'), findsOneWidget);
    expect(find.text('保存された工事'), findsNothing);
    expect(hosted.writes, 0); expect(api.writes, 0);
    host.navigator.currentState!.pop(); await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('two physical backs return child then host without recursion', (tester) async {
    final api = _Api(); final host = await _mount(tester, api);
    await _history(tester);
    await tester.binding.handlePopRoute(); await tester.pumpAndSettle();
    expect(find.byType(SiteOrderWorkflowPage), findsNothing);
    expect(find.text('注文書を見る'), findsOneWidget);
    await tester.binding.handlePopRoute(); await tester.pumpAndSettle();
    expect(find.text('現場を開く'), findsOneWidget);
    expect(host.results, [null]); expect(api.uiRetired, isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets('stale close cannot pop a root dialog opened before the frame', (tester) async {
    final api = _Api(); final host = await _mount(tester, api);
    final close = tester.widget<IconButton>(find.byWidgetPredicate((widget) =>
      widget is IconButton && widget.tooltip == '閉じる')).onPressed!;
    close();
    unawaited(showDialog<void>(context: host.navigator.currentContext!,
      builder: (_) => const AlertDialog(title: Text('ルート側の確認'))));
    await tester.pumpAndSettle();
    expect(find.text('ルート側の確認'), findsOneWidget);
    expect(host.results, isEmpty);
    host.navigator.currentState!.pop(); await tester.pumpAndSettle();
    expect(find.text('注文書を見る'), findsOneWidget);
  });
  testWidgets('narrow enlarged text keeps all actions scrollable', (tester) async {
    tester.view.devicePixelRatio = 1; tester.view.physicalSize = const Size(320, 700);
    addTearDown(tester.view.resetDevicePixelRatio); addTearDown(tester.view.resetPhysicalSize);
    final api = _Api(); await _mount(tester, api, textScaler: const TextScaler.linear(2));
    final context = tester.element(find.byType(SiteOrderSiteActionsPage));
    final media = MediaQuery.of(context);
    expect(media.size.width, 320); expect(media.textScaler.scale(10), 20);
    await tester.ensureVisible(find.text('過去の注文書'));
    expect(tester.takeException(), isNull);
  });
}

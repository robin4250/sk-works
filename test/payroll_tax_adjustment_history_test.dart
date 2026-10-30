import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/auth/app_auth_mutation_gateway.dart';
import 'package:sk_works/features/payroll/payroll_tax_adjustment_history.dart';
import 'package:sk_works/features/payroll/individual_payroll_settings_page.dart';
import 'package:sk_works/features/payroll/individual_payroll_settings_repository.dart';
import 'package:sk_works/features/payroll/resident_tax_capability.dart';

const company = '10000000-0000-0000-0000-000000000001';
const foreign = '10000000-0000-0000-0000-000000000002';
const worker = '40000000-0000-0000-0000-000000000001';
const actor = '00000000-0000-0000-0000-000000000001';
const sid = '70000000-0000-0000-0000-000000000001';

Map<String, dynamic> item({Map<String, dynamic>? before, Map<String, dynamic>? after}) => {
  'starts_on': '2026-10-01', 'version': 2, 'reason': '通知書の金額へ訂正',
  'actor_id': actor, 'changed_at': '2026-10-30T01:02:00+00:00',
  'before_value': before ?? {'deduction_overrides': <String, dynamic>{}},
  'after_value': after ?? {'deduction_overrides': {'health_insurance': 5100}},
};
Map<String, dynamic> response({List<Map<String, dynamic>>? items}) => {
  'contract_version': 1, 'company_id': company, 'worker_id': worker,
  'items': items ?? [item()], 'truncated': false,
};
PayrollTaxHistorySnapshot parsed([Map<String, dynamic>? raw]) =>
    PayrollTaxHistorySnapshot.fromJson(raw ?? response(), companyId: company, workerId: worker);

class _Source extends PayrollTaxHistorySource {
  @override final String companyId = company;
  @override final String workerId = worker;
  bool current = true, closed = false;
  @override bool get isCurrent => current && !closed;
  Object? error;
  int reads = 0;
  PayrollTaxHistorySnapshot value = parsed();
  Completer<PayrollTaxHistorySnapshot>? pending;
  @override Future<PayrollTaxHistorySnapshot> load() async {
    reads++; if (error != null) throw error!;
    if (pending != null) return await pending!.future;
    return value;
  }
  @override void retire() { if (current) { current = false; notifyListeners(); } }
  @override void dispose() { closed = true; super.dispose(); }
}

class _Wire extends http.BaseClient {
  final int expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
  String sessionId = sid, currentCompany = company;
  bool denyAfterHistory = false, missing = false;
  int historyReads = 0;
  final calls = <String>[], headers = <String?>[];
  final params = <Map<String, dynamic>>[];
  Completer<void>? holdHistory, holdLogout;
  Map<String, dynamic> get session => {
    'access_token': token, 'refresh_token': 'fixture-refresh', 'expires_in': 3600,
    'expires_at': expiry, 'token_type': 'bearer', 'user': {
      'id': actor, 'aud': 'authenticated', 'role': 'authenticated',
      'created_at': '2026-01-01T00:00:00Z',
    },
  };
  String get token {
    String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    return '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part({'sub': actor, 'session_id': sessionId, 'role': 'authenticated', 'exp': expiry})}.${part('fixture-signature')}';
  }
  @override Future<http.StreamedResponse> send(http.BaseRequest request) async {
    Object value; var status = 200;
    if (request.url.path.endsWith('/auth/v1/token')) {
      value = session;
    } else if (request.url.path.endsWith('/auth/v1/logout')) {
      await holdLogout?.future; value = {};
    } else {
      final name = request.url.pathSegments.last;
      calls.add(name); headers.add(request.headers['Authorization']);
      params.add(request is http.Request ? Map<String, dynamic>.from(jsonDecode(request.body) as Map) : {});
      if (name == 'payroll_workspace') {
        value = {'company_id': currentCompany,
          'permissions': {'view': !(denyAfterHistory && historyReads > 0)},
          'workers': [{'id': worker, 'name': '検証メンバー'}]};
      } else if (name == 'read_worker_payroll_tax_adjustment_history') {
        historyReads++; await holdHistory?.future;
        value = missing ? {'code': 'PGRST202', 'message': 'private SQL implementation detail'} : response();
        if (missing) status = 404;
      } else {
        throw StateError('Unexpected RPC $name');
      }
    }
    return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(value))), status,
      headers: {'content-type': 'application/json'}, request: request);
  }
}

Future<SupabaseClient> clientFor(_Wire wire) async {
  final client = SupabaseClient('https://synthetic.invalid', 'synthetic-public',
    httpClient: wire, authOptions: const AuthClientOptions(autoRefreshToken: false));
  await client.auth.setInitialSession(jsonEncode(wire.session));
  await Future<void>.value();
  return client;
}

class _ParentRepository extends IndividualPayrollSettingsRepository {
  _ParentRepository(super.client) : super.forTesting();
  int writes = 0;
  @override Future<IndividualPayrollWorkspace> loadWorkspace() async => const IndividualPayrollWorkspace(
    canView: true, canEdit: false, isAdmin: false, companyId: company,
    workers: [IndividualPayrollWorker(id: worker, name: '検証メンバー')]);
  @override Future<bool> supportsPaidLeaveWages() async => false;
  @override Future<ResidentTaxCapability> residentTaxCapability() async => ResidentTaxCapability.legacy;
  @override Future<IndividualPayrollSetting> loadSetting(String workerId) async =>
      IndividualPayrollSetting(workerId: workerId, values: {'company_id': company, 'pay_type': 'daily'});
  @override Future<void> saveSetting({required String workerId, required Map<String, dynamic> values}) async { writes++; }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('parses the exact existing read receipt and distinguishes automatic from explicit zero', () {
    expect(parsed().items.single.changes.single.before, '修正なし');
    expect(parsed().items.single.changes.single.after, '5100円');
    final zero = parsed(response(items: [item(after: {'deduction_overrides': {'health_insurance': 0}})]));
    expect(zero.items.single.changes.single.after, '0円');
    final automatic = parsed(response(items: [item(before: {'deduction_overrides': {'health_insurance': 5100}}, after: {'deduction_overrides': {}})]));
    expect(automatic.items.single.changes.single.after, '修正なし');
  });
  test('rejects foreign scope, wrong version, oversized/duplicate/private rows and invalid months', () {
    for (final raw in [
      {...response(), 'company_id': foreign}, {...response(), 'worker_id': foreign},
      {...response(), 'contract_version': 2}, {...response(), 'truncated': 'false'},
      {...response(), 'items': List.generate(101, (_) => item())},
      response(items: [item(), item()]), response(items: [{...item(), 'session_id': sid}]),
      response(items: [{...item(), 'starts_on': '2026-13-01'}]),
      response(items: [{...item(), 'reason': 'x' * 1001}]),
    ]) { expect(() => parsed(raw), throwsFormatException); }
  });
  test('the SDK read sends exact scope with captured authorization and no capability/save calls', () async {
    final wire = _Wire();
    final sdk = await clientFor(wire);
    final source = PayrollTaxHistoryRepository(sdk, companyId: company, workerId: worker);
    try {
      expect((await source.load()).items.length, 1);
      expect(wire.calls, ['payroll_workspace', 'read_worker_payroll_tax_adjustment_history', 'payroll_workspace']);
      expect(wire.params[1], {'p_company_id': company, 'p_worker_id': worker});
      expect(wire.headers.every((value) => value == 'Bearer ${wire.token}'), isTrue);
    } finally { source.dispose(); await sdk.dispose(); }
  });
  test('workspace role loss after history response refuses publication and retires the source', () async {
    final wire = _Wire()..denyAfterHistory = true;
    final client = await clientFor(wire);
    final source = PayrollTaxHistoryRepository(client, companyId: company, workerId: worker);
    try {
      await expectLater(source.load(), throwsStateError);
      expect(source.isCurrent, isFalse);
    } finally { source.dispose(); await client.dispose(); }
  });
  test('a changed company refuses the history RPC instead of using a stale worker', () async {
    final wire = _Wire()..currentCompany = foreign;
    final client = await clientFor(wire);
    final source = PayrollTaxHistoryRepository(client, companyId: company, workerId: worker);
    try {
      await expectLater(source.load(), throwsStateError);
      expect(wire.calls, ['payroll_workspace']);
    } finally { source.dispose(); await client.dispose(); }
  });
  test('SDK A-B-A authentication cannot publish a late history or revive the old scope', () async {
    final wire = _Wire()..holdHistory = Completer<void>();
    final client = await clientFor(wire);
    final source = PayrollTaxHistoryRepository(client, companyId: company, workerId: worker);
    try {
      final pending = source.load();
      final rejected = expectLater(pending, throwsStateError);
      for (var i = 0; i < 50 && wire.historyReads == 0; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(wire.historyReads, 1);
      wire.sessionId = '70000000-0000-0000-0000-000000000002';
      await client.auth.signInWithPassword(email: 'fixture@example.invalid', password: 'fixture-password');
      wire.sessionId = sid;
      await client.auth.signInWithPassword(email: 'fixture@example.invalid', password: 'fixture-password');
      wire.holdHistory!.complete();
      await rejected;
      expect(source.isCurrent, isFalse);
      expect(wire.historyReads, 1);
    } finally {
      if (!wire.holdHistory!.isCompleted) wire.holdHistory!.complete();
      source.dispose(); await client.dispose();
    }
  });
  test('a missing module is unavailable and never represented as an empty history', () async {
    final wire = _Wire()..missing = true;
    final client = await clientFor(wire);
    final source = PayrollTaxHistoryRepository(client, companyId: company, workerId: worker);
    try { await expectLater(source.load(), throwsA(isA<PayrollTaxHistoryUnavailable>())); }
    finally { source.dispose(); await client.dispose(); }
  });
  testWidgets('history displays reasons and before/after values without edit controls', (tester) async {
    final source = _Source();
    await tester.pumpWidget(MaterialApp(home: PayrollTaxAdjustmentHistoryPage(
      companyId: company, workerId: worker, workerName: '検証メンバー', sourceOverride: source)));
    await tester.pumpAndSettle();
    expect(find.text('通知書の金額へ訂正'), findsOneWidget);
    await tester.tap(find.text('変更内容')); await tester.pumpAndSettle();
    expect(find.text('健康保険料の修正額：修正なし → 5100円'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('保存'), findsNothing);
    expect(find.text('閉じる'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('empty, unavailable and raw backend error states are distinct', (tester) async {
    for (final kind in ['empty', 'unavailable', 'error']) {
      final source = _Source();
      if (kind == 'empty') source.value = parsed(response(items: []));
      if (kind == 'unavailable') source.error = PayrollTaxHistoryUnavailable();
      if (kind == 'error') source.error = StateError('private SQL implementation detail');
      await tester.pumpWidget(MaterialApp(home: PayrollTaxAdjustmentHistoryPage(
        key: ValueKey(kind), companyId: company, workerId: worker, workerName: '検証メンバー', sourceOverride: source)));
      await tester.pumpAndSettle();
      expect(find.text('このメンバーの変更履歴はまだありません。'), kind == 'empty' ? findsOneWidget : findsNothing);
      expect(find.textContaining('まだ利用できません'), kind == 'unavailable' ? findsOneWidget : findsNothing);
      expect(find.textContaining('private SQL'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    }
  });
  testWidgets('invalidation removes visible data and late reads cannot restore it', (tester) async {
    final source = _Source();
    await tester.pumpWidget(MaterialApp(home: PayrollTaxAdjustmentHistoryPage(
      companyId: company, workerId: worker, workerName: '検証メンバー', sourceOverride: source)));
    await tester.pumpAndSettle();
    source.pending = Completer<PayrollTaxHistorySnapshot>();
    await tester.tap(find.text('再読み込み')); await tester.pump();
    source.retire(); await tester.pump();
    source.pending!.complete(parsed()); await tester.pumpAndSettle();
    expect(find.text('通知書の金額へ訂正'), findsNothing);
    expect(find.text('検証メンバー'), findsNothing);
    expect(find.textContaining('閉じて開き直して'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('backgrounding hides history permanently for this route', (tester) async {
    final source = _Source();
    await tester.pumpWidget(MaterialApp(home: PayrollTaxAdjustmentHistoryPage(
      companyId: company, workerId: worker, workerName: '検証メンバー', sourceOverride: source)));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused); await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed); await tester.pump();
    expect(find.text('通知書の金額へ訂正'), findsNothing);
    expect(source.reads, 1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('320px enlarged text retains scrolling and close without overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 700); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final source = _Source()..value = parsed({...response(items: [{...item(), 'reason': '確認した変更理由。' * 30}]), 'truncated': true});
    await tester.pumpWidget(MaterialApp(builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.6)), child: child!),
      home: PayrollTaxAdjustmentHistoryPage(companyId: company, workerId: worker,
        workerName: '検証メンバー', sourceOverride: source)));
    await tester.pumpAndSettle();
    expect(find.text('閉じる'), findsOneWidget); expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('logout intent hides loaded SDK data before remote logout completes', (tester) async {
    final wire = _Wire()..holdLogout = Completer<void>();
    final client = await clientFor(wire);
    final source = PayrollTaxHistoryRepository(client, companyId: company, workerId: worker);
    await tester.pumpWidget(MaterialApp(home: PayrollTaxAdjustmentHistoryPage(companyId: company,
      workerId: worker, workerName: '検証メンバー', sourceOverride: source)));
    await tester.runAsync(() async { await Future<void>.delayed(const Duration(milliseconds: 30)); });
    await tester.pumpAndSettle();
    expect(find.text('通知書の金額へ訂正'), findsOneWidget);
    final logout = AppAuthMutationGateway.forClient(client).signOut();
    await tester.pump();
    expect(find.text('通知書の金額へ訂正'), findsNothing);
    wire.holdLogout!.complete(); await tester.runAsync(() async { await logout; });
    await tester.pumpWidget(const SizedBox()); await client.dispose();
  });
  testWidgets('the existing individual page opens the selected read-only history without saving', (tester) async {
    final client = SupabaseClient('https://synthetic.invalid', 'synthetic-public',
      httpClient: MockClient((_) async => http.Response('{}', 404)),
      authOptions: const AuthClientOptions(autoRefreshToken: false));
    final repository = _ParentRepository(client);
    await tester.pumpWidget(MaterialApp(home: IndividualPayrollSettingsPage(repository: repository)));
    await tester.pumpAndSettle();
    final entry = find.byKey(const ValueKey('payroll-tax-adjustment-history-open'));
    await tester.ensureVisible(entry); await tester.tap(entry); await tester.pumpAndSettle();
    final page = tester.widget<PayrollTaxAdjustmentHistoryPage>(find.byType(PayrollTaxAdjustmentHistoryPage));
    expect(page.companyId, company); expect(page.workerId, worker); expect(page.workerName, '検証メンバー');
    expect(repository.writes, 0);
    await tester.tap(find.text('閉じる')); await tester.pumpAndSettle();
    expect(find.byType(IndividualPayrollSettingsPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); await client.dispose();
  });
}

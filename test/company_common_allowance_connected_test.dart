import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/company_common_payroll_page.dart';
import 'package:sk_works/features/payroll/company_common_allowance_repository.dart';
import 'package:sk_works/features/payroll/company_common_allowance_pending_store.dart';

const company = 'company';
const actor = 'actor';
const itemId = '10000000-0000-0000-0000-000000000001';
List<Map<String, dynamic>> legacy() => [for (var i = 1; i <= 3; i++) {'slot': i, 'id': '30000000-0000-0000-0000-${i.toString().padLeft(12,'0')}', 'generation': 1, 'name': i == 1 ? '旧原値' : null, 'source_unit': '回', 'amount_yen': i * 100}];
Map<String, dynamic> source() => {'legacy_adopted': true, 'legacy_version': 1, 'legacy_slots': [for (final x in legacy()) {'slot': x['slot'], 'name': x['name'], 'unit': x['source_unit'], 'amount_yen': x['amount_yen']}], 'tax_rate': 10, 'welfare_rate': 15};
Map<String, dynamic> state({int version = 0, bool canEdit = true, List<Map<String, dynamic>> items = const [], List<Map<String, dynamic>>? legacyValues}) => {
 'contract_version': 1, 'company_id': company, 'version': version, 'can_edit': canEdit, 'items': items,
 'expected_source': source(), 'tax_rate': 10, 'welfare_rate': 15,
 'legacy_refs': [for (final x in legacyValues ?? legacy()) {...x, 'applicability': 'all', 'section': 'earning', 'unit': 'day'}],
};
CompanyCommonAllowancePending command({String who = actor}) => CompanyCommonAllowancePending(actorId: who, companyId: company, payrollType: 'hourly', expectedVersion: 0, expectedSource: source(), legacySlots: legacy(), confirmAdoption: false, requestId: '20000000-0000-0000-0000-000000000001', items: const [{'id': null, 'client_key': 'new-unit-item-0', 'section': 'earning', 'unit': 'hour', 'name': '共通', 'amount_yen': 100}]);
class MemoryStore implements CompanyCommonAllowancePendingStore {
 CompanyCommonAllowancePending? pending;
 @override Future<CompanyCommonAllowancePending?> read(String actorId, String companyId) async => pending;
 @override Future<void> write(CompanyCommonAllowancePending p) async { if (pending != null) throw StateError('existing'); pending = p; }
 @override Future<void> clear(CompanyCommonAllowancePending p) async { expect(pending?.toJson(), p.toJson()); pending = null; }
}
class FakeRepository implements CompanyCommonAllowanceRepository {
 String? who = actor;
 @override String? get actorId => who;
 final changes = StreamController<String?>.broadcast(sync: true);
 @override Stream<String?> get actorChanges => changes.stream;
 CompanyCommonAllowanceState value = CompanyCommonAllowanceState.parse(state(), company);
 bool loseReply = false, denyRead = false;
 int writes = 0, reads = 0, receipts = 0, counter = 0;
 Completer<void>? gate;
 CompanyCommonAllowancePending? last;
 @override Future<CompanyCommonAllowanceState> read(String companyId) async { reads++; if (denyRead) throw StateError('offline'); return value; }
 @override Future<CompanyCommonAllowanceState> save(CompanyCommonAllowancePending pending) async {
  writes++; last = pending; await gate?.future;
  value = CompanyCommonAllowanceState.parse(state(version: value.version + 1, legacyValues: pending.legacySlots, items: [
   ...value.items.where((x) => x['payroll_type'] != pending.payrollType),
   for (final x in pending.items) {'id': x['id'] ?? '10000000-0000-0000-0000-${(++counter).toString().padLeft(12, '0')}', 'payroll_type': pending.payrollType, 'section': x['section'], 'unit': x['unit'], 'name': x['name'], 'amount_yen': x['amount_yen']},
  ]), company);
  if (loseReply) throw StateError('lost reply after commit'); return value;
 }
 @override Future<CompanyCommonAllowanceState?> reconcile(CompanyCommonAllowancePending pending) async { receipts++; return last == null ? null : value; }
}
Future<void> show(WidgetTester tester, FakeRepository repo, MemoryStore store) async {
 tester.view.physicalSize = const Size(900, 1200); tester.view.devicePixelRatio = 1;
 await tester.pumpWidget(MaterialApp(home: CompanyCommonPayrollPage(companyId: company, repository: repo, pendingStore: store)));
 await tester.pumpAndSettle();
}
Future<void> add(WidgetTester tester, String name) async {
 await tester.scrollUntilVisible(find.text('追加'), 250, scrollable: find.byType(Scrollable).first); await tester.pumpAndSettle();
 await tester.tap(find.text('追加')); await tester.pumpAndSettle();
 final names = find.byWidgetPredicate((widget) => widget is TextField && widget.decoration?.labelText == '項目名');
 final rates = find.byWidgetPredicate((widget) => widget is TextField && widget.decoration?.labelText != '項目名');
 await tester.ensureVisible(names.last); await tester.enterText(names.last, name); await tester.ensureVisible(rates.last); await tester.enterText(rates.last, '1200');
}
Future<void> save(WidgetTester tester) async {
 await tester.scrollUntilVisible(find.text('登録'), 250, scrollable: find.byType(Scrollable).first); await tester.pumpAndSettle();
 await tester.tap(find.text('登録')); await tester.pumpAndSettle();
}
void main() {
 tearDown(() {});
 test('strict contract preserves units and stable IDs; wrong company and malformed values reject', () {
  for (final unit in ['hour', 'day', 'month']) {
   final value = state(items: [{'id': itemId, 'payroll_type': 'hourly', 'section': 'earning', 'unit': unit, 'name': '同名', 'amount_yen': 10}]);
   expect(CompanyCommonAllowanceState.parse(value, company).items.single['unit'], unit);
   expect(() => CompanyCommonAllowanceState.parse(value, 'other'), throwsFormatException);
   expect(() => CompanyCommonAllowanceState.parse({...value, 'version': -1}, company), throwsFormatException);
  }
 });
 test('actual isolated SQL candidate responses parse and receipt matches original command exactly', () async {
  // PGlite executed PR1152 SQL; all actors, UUIDs and prices are synthetic.
  // This is SQL/client serialization coverage, not a live DataAPI test.
  final fixture = jsonDecode(File('test/fixtures/company_common_allowance_sql_response.json').readAsStringSync()) as Map;
  final receipt = Map<String, dynamic>.from(fixture['receipt'] as Map);
  final payload = Map<String, dynamic>.from(receipt['request_payload'] as Map);
  final p = CompanyCommonAllowancePending.parse({...payload, 'actor_id': receipt['actor_id'], 'company_id': receipt['company_id'], 'request_id': receipt['request_id']});
  var corrupt = false;
  final repo = SupabaseCompanyCommonAllowanceRepository.forTesting(actor: () => p.actorId, invoke: (name, args) async {
   if (name == 'read_company_common_allowances_admin') return fixture['initial'];
   if (name == 'save_company_common_allowances') { expect(args['p_expected_source'], payload['expected_source']); expect(args['p_legacy_slots'], payload['legacy_slots']); expect(args['p_items'], payload['items']); return fixture['saved']; }
   return corrupt ? {...receipt, 'actor_id': 'wrong-actor'} : receipt;
  });
  final before = await repo.read(p.companyId); expect(before.expectedSource['legacy_adopted'], false);
  final after = await repo.save(p); expect(after.legacyRefs[0]['id'], isNot(after.legacyRefs[1]['id'])); expect(after.items.map((x) => x['unit']).toSet(), {'hour', 'day', 'month'});
  expect((await repo.reconcile(p))!.version, after.version);
  corrupt = true; await expectLater(repo.reconcile(p), throwsFormatException);
 });
 test('repository uses only company-common RPCs and reconciles exact actor payload receipt', () async {
  final pending = command(); final names = <String>[];
  final result = {...state(version: 1, items: [{'id': itemId, 'payroll_type': 'hourly', 'section': 'earning', 'unit': 'hour', 'name': '共通', 'amount_yen': 100}]), 'request_id': pending.requestId, 'committed_version': 1, 'id_map': [{'client_key': 'new-unit-item-0', 'id': itemId}]};
  var wrongActor = false;
  final repo = SupabaseCompanyCommonAllowanceRepository.forTesting(actor: () => actor, invoke: (name, args) async {
   names.add(name); expect(args['p_company_id'], company);
   if (name == 'read_company_common_allowances_admin') return state();
   if (name == 'save_company_common_allowances') { expect(args['p_items'], pending.items); expect(args.containsKey('p_worker_id'), false); expect(args.containsKey('p_month'), false); return result; }
   return {'contract_version': 1, 'company_id': company, 'request_id': pending.requestId, 'found': true, 'operation': 'allowances', 'actor_id': wrongActor ? 'other' : actor, 'payroll_type': 'hourly', 'expected_version': 0, 'request_payload': pending.payload, 'committed_version': 1, 'result': result};
  });
  await repo.read(company); expect((await repo.save(pending)).items.single['id'], itemId);
  expect((await repo.reconcile(pending))!.version, 1);
  wrongActor = true; await expectLater(repo.reconcile(pending), throwsFormatException);
  expect(names, ['read_company_common_allowances_admin', 'save_company_common_allowances', 'read_company_common_allowance_request', 'read_company_common_allowance_request']);
 });
 test('private file journal survives restart and never crosses actors or overwrites pending command', () async {
  final folder = await Directory.systemTemp.createTemp('common-pending-'); addTearDown(() => folder.delete(recursive: true));
  var who = actor;
  final store = FileCompanyCommonAllowancePendingStore(currentActor: () => who, directory: () async => folder);
  final p = command(); await store.write(p); await expectLater(store.write(p), throwsStateError);
  final restarted = FileCompanyCommonAllowancePendingStore(currentActor: () => actor, directory: () async => folder);
  expect((await restarted.read(actor, company))!.toJson(), p.toJson()); expect(await restarted.read(actor, 'other'), isNull);
  who = 'other'; await expectLater(store.read(actor, company), throwsStateError);
  await restarted.clear(p); expect(await restarted.read(actor, company), isNull);
 });
 testWidgets('three tab rows follow hourly daily monthly then unit then section', (tester) async {
  final repo = FakeRepository(), store = MemoryStore(); await show(tester, repo, store);
  final hourly = find.widgetWithText(OutlinedButton, '時給'), daily = find.widgetWithText(OutlinedButton, '日給');
  expect(tester.getTopLeft(hourly).dx, lessThan(tester.getTopLeft(daily).dx));
  expect(tester.getTopLeft(hourly).dy, lessThan(tester.getTopLeft(find.text('時間単位')).dy));
  expect(tester.getTopLeft(find.text('時間単位')).dy, lessThan(tester.getTopLeft(find.text('支給')).dy));
  await tester.pumpWidget(const SizedBox()); tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio();
 });
 testWidgets('hour day month additions roundtrip; edit keeps ID and delete affects only selected type', (tester) async {
  final repo = FakeRepository(), store = MemoryStore(); await show(tester, repo, store);
  for (final unit in ['時間単位', '日単位', '月単位']) {
   await tester.tap(find.widgetWithText(OutlinedButton, unit)); await tester.pump(); await add(tester, unit); await save(tester);
   expect(find.text('保存完了'), findsOneWidget); await tester.tap(find.text('閉じる')); await tester.pumpAndSettle();
   expect(find.text(unit), findsWidgets);
  }
  expect(repo.value.items.map((x) => x['unit']).toSet(), {'hour', 'day', 'month'});
  final id = repo.value.items.last['id'];
  await tester.enterText(find.byKey(ValueKey('$id-name')), '編集済み'); await save(tester); await tester.tap(find.text('閉じる')); await tester.pumpAndSettle();
  expect(repo.value.items.last['id'], id); expect(repo.value.items.last['name'], '編集済み');
  await tester.pumpWidget(const SizedBox()); await show(tester, repo, store);
  await tester.tap(find.widgetWithText(OutlinedButton, '月単位')); await tester.pump(); expect(find.text('編集済み'), findsOneWidget);
  await tester.tap(find.widgetWithText(TextButton, '削除')); await tester.pumpAndSettle(); await save(tester); await tester.tap(find.text('閉じる')); await tester.pumpAndSettle();
  expect(repo.value.items.length, 2); expect(repo.value.items.any((x) => x['id'] == id), false);
  await tester.pumpWidget(const SizedBox()); tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio();
 });
 testWidgets('unknown result retains input and durable command; receipt lookup never resends', (tester) async {
  final repo = FakeRepository()..loseReply = true; final store = MemoryStore(); await show(tester, repo, store);
  await add(tester, '失敗保持'); await save(tester); expect(store.pending, isNotNull); expect(repo.writes, 1); expect(find.text('失敗保持'), findsOneWidget);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused); await tester.pump();
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed); await tester.pumpAndSettle();
  await tester.tap(find.text('保存状態を確認')); await tester.pumpAndSettle(); expect(repo.writes, 1); expect(repo.receipts, 1); expect(store.pending, isNull);
  await tester.tap(find.text('閉じる')); await tester.pumpAndSettle(); expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '追加')).onPressed, isNotNull); await tester.pumpWidget(const SizedBox()); tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio();
 });
 testWidgets('viewer cannot add; background preserves drafts and actor switch destroys private subtree', (tester) async {
  final repo = FakeRepository()..value = CompanyCommonAllowanceState.parse(state(canEdit: false), company); final store = MemoryStore(); await show(tester, repo, store);
  expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '追加')).onPressed, isNull);
  await tester.pumpWidget(const SizedBox()); repo.value = CompanyCommonAllowanceState.parse(state(), company); await show(tester, repo, store); await add(tester, '未保存');
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused); await tester.pump(); expect(find.text('未保存'), findsNothing); expect(find.text('未保存', skipOffstage: false), findsOneWidget);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed); await tester.pumpAndSettle(); expect(find.text('未保存'), findsOneWidget);
  repo.who = 'other'; await tester.pump(const Duration(seconds: 1)); expect(find.text('未保存', skipOffstage: false), findsNothing); expect(repo.writes, 0);
  await tester.pumpWidget(const SizedBox()); tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio();
 });
 testWidgets('legacy three are first in day earnings and share edits across salary types without copies', (tester) async {
  final repo = FakeRepository(), store = MemoryStore(); await show(tester, repo, store);
  await tester.tap(find.widgetWithText(OutlinedButton, '日単位')); await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('legacy-1-name')), findsOneWidget);
  await tester.enterText(find.byKey(const ValueKey('legacy-1-name')), '共通の編集');
  await tester.tap(find.widgetWithText(OutlinedButton, '日給')); await tester.pumpAndSettle();
  expect(tester.widget<TextField>(find.byKey(const ValueKey('legacy-1-name'))).controller!.text, '共通の編集');
  await tester.ensureVisible(find.byKey(const ValueKey('legacy-1-unit'))); await tester.enterText(find.byKey(const ValueKey('legacy-1-unit')), '件');
  await save(tester); await tester.tap(find.text('閉じる')); await tester.pumpAndSettle();
  expect(repo.value.legacyRefs.first['name'], '共通の編集'); expect(repo.value.legacyRefs.first['source_unit'], '件');
  expect(repo.value.legacyRefs.first['unit'], 'day'); expect(repo.value.legacyRefs.first['id'], legacy().first['id']); expect(repo.value.items, isEmpty);
  await tester.tap(find.widgetWithText(OutlinedButton, '控除')); await tester.pumpAndSettle(); expect(find.byKey(const ValueKey('legacy-1-name')), findsNothing);
  await tester.pumpWidget(const SizedBox()); tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio();
 });
 testWidgets('in-flight registration cannot issue duplicate commands', (tester) async {
  final repo = FakeRepository()..gate = Completer<void>(); final store = MemoryStore(); await show(tester, repo, store);
  await add(tester, '一回だけ'); await tester.ensureVisible(find.text('登録')); await tester.tap(find.text('登録')); await tester.pump(); await tester.pump();
  expect(repo.writes, 1); expect(store.pending, isNotNull);
  expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '登録中')).onPressed, isNull);
  repo.gate!.complete(); await tester.pumpAndSettle(); await tester.tap(find.text('閉じる')); await tester.pumpAndSettle(); expect(repo.writes, 1);
  await tester.pumpWidget(const SizedBox()); tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio();
 });
 testWidgets('logout and same actor return cannot revive old draft', (tester) async {
  final repo = FakeRepository(), store = MemoryStore(); await show(tester, repo, store); await add(tester, '前の入力');
  repo.changes.add(null); repo.changes.add(actor); await tester.pump();
  expect(find.text('前の入力', skipOffstage: false), findsNothing); expect(repo.writes, 0);
  await tester.pumpWidget(const SizedBox()); await repo.changes.close(); tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio();
 });
 testWidgets('first legacy adoption needs explicit confirmation and cancel sends nothing', (tester) async {
  final raw = state(); raw['expected_source'] = {...source(), 'legacy_adopted': false};
  final repo = FakeRepository()..value = CompanyCommonAllowanceState.parse(raw, company); final store = MemoryStore(); await show(tester, repo, store);
  await add(tester, '未採用の追加'); await save(tester); expect(find.text('既存手当を引き継いで保存'), findsOneWidget);
  await tester.tap(find.text('戻る')); await tester.pumpAndSettle(); expect(repo.writes, 0); expect(store.pending, isNull); expect(find.text('未採用の追加'), findsOneWidget);
  await tester.pumpWidget(const SizedBox()); tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio();
 });
}

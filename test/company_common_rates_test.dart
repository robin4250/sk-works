import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/settings/company_common_rates_page.dart';
import 'package:sk_works/features/settings/company_common_rates_pending.dart';
import 'package:sk_works/features/settings/company_common_rates_repository.dart';

const company = '10000000-0000-0000-0000-000000000001';
const actor = '20000000-0000-0000-0000-000000000001';
Map<String,dynamic> fixtures() => commonRatesObject(jsonDecode(File('test/fixtures/company_common_rates_sql_response.json').readAsStringSync()));
CompanyCommonRatesRequest fixtureRequest() => CompanyCommonRatesRequest.parse({'journal_version':1,'company_id':company,'actor_id':actor,'request_id':fixtures()['receipt']['request_id'],'request_payload':fixtures()['receipt']['request_payload']},company,actor);
class MemoryStore implements CompanyCommonRatesPendingStore {
 CompanyCommonRatesRequest? pending;
 @override String actorId() => actor;
 @override Future<CompanyCommonRatesRequest?> read(String companyId) async => pending;
 @override Future<void> write(CompanyCommonRatesRequest request) async { if (pending != null) throw StateError('existing'); pending = request; }
 @override Future<void> clear(CompanyCommonRatesRequest request) async { expect(pending?.toJson(), request.toJson()); pending = null; }
}
class FakeRates implements CompanyCommonRatesRepository {
 @override String? actorId = actor;
 final events = StreamController<String?>.broadcast(sync:true);
 @override Stream<String?> get actorChanges => events.stream;
 CompanyCommonRatesState current = CompanyCommonRatesState.parse(fixtures()['initial'],company);
 bool loseReply = false, missing = false, denyRead = false, receiptFound = true;
 int writes = 0, receipts = 0;
 Completer<void>? gate;
 CompanyCommonRatesRequest? last;
 @override Future<CompanyCommonRatesState> read(String companyId) async { if (missing) throw const CompanyCommonRatesUnavailable(); if (denyRead) throw StateError('offline'); return current; }
 @override Future<CompanyCommonRatesState> save(CompanyCommonRatesRequest request) async {
  writes++; last = request; await gate?.future;
  current = request.validateCommit({'contract_version':1,'company_id':company,'can_edit':true,'version':request.expectedVersion+1,'rates':request.rates,'request_id':request.requestId,'committed_version':request.expectedVersion+1,'id_map':[]});
  if (loseReply) throw StateError('lost response'); return current;
 }
 @override Future<CompanyCommonRatesState?> receipt(CompanyCommonRatesRequest request) async { receipts++; return receiptFound ? current : null; }
}
Future<void> mount(WidgetTester tester, FakeRates repo, MemoryStore store) async {
 tester.view.physicalSize = const Size(900,1200); tester.view.devicePixelRatio = 1;
 await tester.pumpWidget(MaterialApp(home:CompanyCommonRatesPage(companyId:company,repository:repo,pendingStore:store))); await tester.pumpAndSettle();
}
Future<void> enter(WidgetTester tester, String value) async { await tester.enterText(find.byKey(const Key('company-common-rates-overtime_hour_rate_yen')),value); await tester.pump(); }
void main() {
 test('actual isolated rates SQL responses and receipt use strict four-column operation', () {
  final data = fixtures(); final request = fixtureRequest();
  expect(CompanyCommonRatesState.parse(data['initial'],company).rates.values, everyElement(0));
  expect(request.validateCommit(data['result']).rates['holiday_day_rate_yen'],32800);
  expect(request.validateReceipt(data['receipt'])!.version,1);
  expect(() => request.validateReceipt({...commonRatesObject(data['receipt']),'operation':'tax'}),throwsFormatException);
  expect(() => CompanyCommonRatesState.parse({...commonRatesObject(data['initial']),'rates':{'overtime_hour_rate_yen':10}},company),throwsFormatException);
  expect(() => CompanyCommonRatesState.parse({...commonRatesObject(data['initial']),'rates':{...request.rates,'early_hour_rate_yen':1.5}},company),throwsFormatException);
  expect(() => CompanyCommonRatesState.parse({...commonRatesObject(data['initial']),'rates':{...request.rates,'night_hour_rate_yen':-1}},company),throwsFormatException);
  expect(() => CompanyCommonRatesState.parse({...commonRatesObject(data['initial']),'rates':{...request.rates,'night_hour_rate_yen':2147483648}},company),throwsFormatException);
 });
 test('rates journal persists exact command, refuses tax namespace, and never overwrites', () async {
  final folder = await Directory.systemTemp.createTemp('rates-journal-'); addTearDown(() => folder.delete(recursive:true));
  final store = FileCompanyCommonRatesPendingStore(currentActor:()=>actor,directory:() async=>folder);
  final request = fixtureRequest(); await store.write(request); await expectLater(store.write(request),throwsStateError);
  final restarted = FileCompanyCommonRatesPendingStore(currentActor:()=>actor,directory:() async=>folder);
  expect((await restarted.read(company))!.toJson(),request.toJson());
  expect(await restarted.read('10000000-0000-0000-0000-000000000002'),isNull);
  expect(() => CompanyCommonRatesRequest.parse({...request.toJson(),'request_payload':{...request.payload,'operation':'tax'}},company,actor),throwsFormatException);
  expect((await folder.list().toList()).single.path,endsWith('sko-company-common-rates-pending-v1'));
  await restarted.clear(request); expect(await restarted.read(company),isNull);
 });
 testWidgets('four old values edit and save through rates-only callback then show completion', (tester) async {
  final repo = FakeRates(), store = MemoryStore(); await mount(tester,repo,store);
  for (final key in companyCommonRateLabels.keys) { expect(find.byKey(Key('company-common-rates-$key')),findsOneWidget); }
  await enter(tester,'5125'); await tester.tap(find.text('保存')); await tester.pumpAndSettle();
  expect(repo.writes,1); expect(repo.last!.rates['overtime_hour_rate_yen'],5125); expect(repo.last!.rates['early_hour_rate_yen'],0);
  expect(find.text('残業・早出などの単価を保存しました。'),findsOneWidget); expect(store.pending,isNull);
  await tester.pumpWidget(const SizedBox()); tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio();
 });
 testWidgets('unknown save survives restart and receipt inspection does not resend', (tester) async {
  final repo = FakeRates()..loseReply=true, store=MemoryStore(); await mount(tester,repo,store); await enter(tester,'5125');
  await tester.tap(find.text('保存')); await tester.pumpAndSettle(); expect(store.pending,isNotNull); expect(repo.writes,1);
  await tester.pumpWidget(const SizedBox()); await mount(tester,repo,store);
  expect(repo.writes,1); expect(repo.receipts,1); expect(store.pending,isNull); expect(find.textContaining('保存を確認しました'),findsOneWidget);
  await tester.pumpWidget(const SizedBox()); tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio();
 });
 testWidgets('missing and mismatched receipts keep journal and disable new save', (tester) async {
  final repo=FakeRates()..loseReply=true..receiptFound=false, store=MemoryStore(); await mount(tester,repo,store); await enter(tester,'5125');
  await tester.tap(find.text('保存')); await tester.pumpAndSettle(); await tester.tap(find.text('保存状態を再確認')); await tester.pumpAndSettle();
  expect(repo.writes,1); expect(store.pending,isNotNull); expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton,'保存')).onPressed,isNull);
  await tester.pumpWidget(const SizedBox()); tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio();
 });
 testWidgets('viewer and unavailable service never permit mutation; overflow integer is rejected', (tester) async {
  final repo=FakeRates()..current=CompanyCommonRatesState.parse(fixtures()['viewer'],company), store=MemoryStore(); await mount(tester,repo,store);
  expect(tester.widget<TextField>(find.descendant(of:find.byKey(const Key('company-common-rates-overtime_hour_rate_yen')),matching:find.byType(TextField))).readOnly,true);
  await tester.pumpWidget(const SizedBox()); repo.current=CompanyCommonRatesState.parse(fixtures()['initial'],company); await mount(tester,repo,store);
  await enter(tester,'2147483648'); await tester.tap(find.text('保存')); await tester.pumpAndSettle(); expect(repo.writes,0); expect(find.text('0〜2147483647の整数で入力してください'),findsWidgets);
  await tester.pumpWidget(const SizedBox()); repo.missing=true; await mount(tester,repo,store); expect(find.textContaining('準備中'),findsOneWidget); expect(repo.writes,0);
  await tester.pumpWidget(const SizedBox()); tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio();
 });
 testWidgets('actor ABA clears rates and rejects late save result without losing confirmation record', (tester) async {
  final repo=FakeRates()..gate=Completer<void>(), store=MemoryStore(); await mount(tester,repo,store); await enter(tester,'5125');
  await tester.tap(find.text('保存')); await tester.pump(); await tester.pump(); expect(repo.writes,1);
  repo.events.add(null); repo.events.add(actor); await tester.pump(); repo.gate!.complete(); await tester.pumpAndSettle();
  expect(find.textContaining('ログイン状態が変わりました'),findsOneWidget); expect(find.text('残業・早出などの単価を保存しました。'),findsNothing); expect(store.pending,isNotNull);
  await tester.pumpWidget(const SizedBox()); await repo.events.close(); tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio();
 });
}

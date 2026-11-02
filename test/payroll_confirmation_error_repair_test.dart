import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/payroll/payroll_confirmation_repository.dart';
import 'package:sk_works/features/payroll/payroll_statement_repository.dart';
import 'package:sk_works/features/payroll/payroll_statement_source_repository.dart';
import 'package:sk_works/features/payroll/payroll_statements_page.dart';
import 'package:sk_works/international/language_controller.dart';
import 'package:sk_works/international/languages/en/english_language_pack.dart';

PayrollStatementRecord row(int revision,{bool blocked=false})=>PayrollStatementRecord(
 id:'synthetic-payslip',companyName:'Synthetic company',workerName:'Synthetic employee',
 periodStart:DateTime(2026,11),periodEnd:DateTime(2026,11,30),grossPay:revision*100,deductions:0,netPay:revision*100,
 revision:revision,workflowState:'draft',detail:{'bank_account':<String,dynamic>{},if(blocked)'tax_calculation':{'blocked':true,'reason':'synthetic blocked'}});
class Fixture {
 int reads=0,mutations=0,renderCalls=0;
 String message='check all employee statements before confirmation';
 bool failRead=false,blockedRefresh=false;
 Completer<List<PayrollStatementRecord>>? refresh;
 late final client=SupabaseClient('https://payroll-repair-fixture.invalid','public-fixture',
  authOptions:const AuthClientOptions(autoRefreshToken:false),
  httpClient:MockClient((request) async {
   expect(request.url.host,'payroll-repair-fixture.invalid');
   expect(request.url.path,'/rest/v1/rpc/confirm_payroll_review_month');
   expect(jsonDecode(request.body),{'p_period_start':'2026-11-01'});
   mutations++;
   return http.Response(jsonEncode({'code':'P0001','message':message,'details':'private-untrusted-detail','hint':'do-not-show'}),400,
    headers:{'content-type':'application/json'},request:request);
  }));
 late final source=PayrollStatementSourceRepository(
  readManagement:(_) async {reads++;if(reads==1)return[row(1)];if(failRead)throw StateError('synthetic source failure');return refresh?.future??[row(2,blocked:blockedRefresh)];},
  readSelf:()async=>throw StateError('must not fallback'),
  readConfirmation:(_)async=>PayrollConfirmationStatus.fromJson({'can_confirm':reads==1,'can_cancel':false,'confirmed':false,'reviewers':<Object>[]}));
 Widget page()=>PayrollStatementPreviewPage(statement:row(99),sourceRepository:source,
  confirmationRepository:PayrollConfirmationRepository.forClient(client),
  previewBuilder:(r){renderCalls++;return Text('verified-preview revision:${r.revision} net:${r.netPay}');});
}
Future<void> pump(WidgetTester t)async {for(var i=0;i<8;i++){await t.pump(const Duration(milliseconds:20));}}
void main(){
 for(final english in [false,true]){
  testWidgets('failed confirmation rereads authoritative source before preview, english=$english',(t)async{
   final previous=SkoLanguageController.pack.value;
   if(english)SkoLanguageController.pack.value=englishLanguagePack;
   addTearDown(()=>SkoLanguageController.pack.value=previous);
   final f=Fixture()..refresh=Completer<List<PayrollStatementRecord>>();await t.runAsync(() async { f.client; });addTearDown(()=>t.runAsync(()=>f.client.dispose()));
   await t.pumpWidget(MaterialApp(home:f.page()));await pump(t);
   expect(find.text('verified-preview revision:1 net:100'),findsOneWidget);
   await t.tap(find.text(english?"Confirm This Month's Payroll":'月の給与を確認' ));await pump(t);
   expect(f.mutations,1);expect(f.reads,2);
   expect(find.textContaining('verified-preview'),findsNothing);
   final callsWhileBlocked=f.renderCalls;
   await pump(t);expect(f.renderCalls,callsWhileBlocked);
   f.refresh!.complete([row(2)]);await pump(t);
   expect(find.text('verified-preview revision:2 net:200'),findsOneWidget);
   expect(find.text('verified-preview revision:1 net:100'),findsNothing);
   expect(find.text(english?'Review every employee payslip before confirming the month’s payroll.':'全従業員の給与明細を確認してから、月の給与を確認してください。'),findsOneWidget);
   expect(find.textContaining('PostgrestException'),findsNothing);expect(find.textContaining('private-untrusted-detail'),findsNothing);
   expect(f.mutations,1,reason:'never automatically repeat a failed mutation');
   await t.pumpWidget(const SizedBox.shrink());
  });
 }
 testWidgets('failed authoritative refresh keeps preview blocked after rejected mutation',(t)async{
  final f=Fixture()..failRead=true;await t.runAsync(() async { f.client; });addTearDown(()=>t.runAsync(()=>f.client.dispose()));
  await t.pumpWidget(MaterialApp(home:f.page()));await pump(t);
  await t.tap(find.text('月の給与を確認'));await pump(t);
  expect(f.reads,2);expect(f.mutations,1);
  expect(find.textContaining('verified-preview'),findsNothing);
  expect(find.textContaining('給与明細を再取得できませんでした'),findsOneWidget);
  expect(find.text('全従業員の給与明細を確認してから、月の給与を確認してください。'),findsOneWidget);
  await t.pumpWidget(const SizedBox.shrink());
 });
 testWidgets('unknown mutation error uses safe message and preserves fresh tax block',(t)async{
  final f=Fixture()..message='unknown-secret-raw-server-error'..blockedRefresh=true;await t.runAsync(() async { f.client; });addTearDown(()=>t.runAsync(()=>f.client.dispose()));
  await t.pumpWidget(MaterialApp(home:f.page()));await pump(t);
  await t.tap(find.text('月の給与を確認'));await pump(t);
  expect(f.reads,2);expect(f.mutations,1);
  expect(find.textContaining('verified-preview'),findsNothing);
  expect(find.textContaining('synthetic blocked'),findsOneWidget);
  expect(find.textContaining('最新の給与明細と確認状況を再取得しました'),findsOneWidget);
  expect(find.textContaining('unknown-secret'),findsNothing);expect(find.textContaining('private-untrusted-detail'),findsNothing);
  await t.pumpWidget(const SizedBox.shrink());
  final held=Fixture()..refresh=Completer<List<PayrollStatementRecord>>();await t.runAsync(() async { held.client; });addTearDown(()=>t.runAsync(()=>held.client.dispose()));
  await t.pumpWidget(MaterialApp(home:held.page()));await pump(t);
  await t.tap(find.text('月の給与を確認'));await pump(t);
  expect(held.reads,2);expect(find.textContaining('verified-preview'),findsNothing);
  final renderedBeforeDispose=held.renderCalls;
  await t.pumpWidget(const SizedBox.shrink());
  held.refresh!.complete([row(3)]);await pump(t);
  expect(held.renderCalls,renderedBeforeDispose);expect(t.takeException(),isNull);
 });
}

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/payroll/company_common_payroll_publication_repository.dart';
import 'package:sk_works/features/payroll/company_common_payroll_publication_panel.dart';

Map<String,dynamic> stateJson(String company,{int version=0,bool canEdit=true,List<Map<String,dynamic>> entries=const []})=>{
 'contract_version':1,'company_id':company,'can_edit':canEdit,'timeline_version':version,'common_version':2,'common_source':{'legacy_adopted':true},'entries':entries};
class FakePublicationRepository implements CommonPayrollPublicationRepository {
 String? key='session-a';final changes=StreamController<String?>.broadcast();bool canEdit=true;bool failOnce=false;
 Completer<CommonPayrollPublicationState>? held;
 final requests=<CommonPayrollPublicationRequest>[];
 @override String? get sessionKey=>key;
 @override Stream<String?> get sessionChanges=>changes.stream;
 @override Future<CommonPayrollPublicationState> read(String companyId) async=>CommonPayrollPublicationState.parse(stateJson(companyId,canEdit:canEdit),companyId);
 @override Future<CommonPayrollPublicationState> publish(CommonPayrollPublicationRequest request) async {
  requests.add(request);if(held!=null)return held!.future;if(failOnce){failOnce=false;throw StateError('fixture network unknown');}
  return CommonPayrollPublicationState.parse(stateJson(request.state.companyId,version:request.state.timelineVersion+1,entries:[{'version':request.state.timelineVersion+1,'payroll_type':request.payrollType,'starts_on':request.startsOn,'request_id':request.requestId}]),request.state.companyId);
 }
}
void main(){
 test('publication response must match company and version contract',(){expect(()=>CommonPayrollPublicationState.parse(stateJson('other'),'company'),throwsStateError);});
 for(final mode in ['valid','same_token_signout_signin','wrong_receipt']){
  test('publication real SDK: $mode',() async {
   const uid='00000000-0000-0000-0000-000000000001';
   final user={'id':uid,'aud':'authenticated','role':'authenticated','email':'fixture@example.invalid','created_at':'2026-01-01T00:00:00Z','app_metadata':{},'user_metadata':{}};
   String part(Object value)=>base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=','');
   final token='${part({'alg':'HS256'})}.${part({'sub':uid,'exp':DateTime.now().millisecondsSinceEpoch~/1000+3600})}.fixture';
   final bodies=<Map<String,dynamic>>[];late SupabaseClient client;
   client=SupabaseClient('https://fixture.invalid','fixture-public',authOptions:const AuthClientOptions(autoRefreshToken:false),httpClient:MockClient((request) async {
    Object? result;
    if(request.url.path=='/auth/v1/token'){result={'access_token':token,'refresh_token':'fixture','token_type':'bearer','expires_in':3600,'user':user};}
    else if(request.url.path=='/rest/v1/rpc/publish_company_common_payroll'){
     expect(request.headers['Authorization'],'Bearer $token');final body=Map<String,dynamic>.from(jsonDecode(request.body) as Map);bodies.add(body);
     if(mode=='same_token_signout_signin'){await client.auth.signOut(scope:SignOutScope.local);await client.auth.signInWithPassword(email:'fixture@example.invalid',password:'fixture');}
     result={'contract_version':1,'company_id':'company','request_id':mode=='wrong_receipt'?'different':body['p_request_id'],'payroll_type':'daily','starts_on':'2026-10-01','publication_version':1,'timeline':stateJson('company',version:1)};
    }else if(request.url.path=='/auth/v1/logout'){return http.Response('',204,request:request);}else{throw StateError('unexpected fixture request');}
    return http.Response(jsonEncode(result),200,headers:{'content-type':'application/json'},request:request);
   }));addTearDown(client.dispose);
   await client.auth.signInWithPassword(email:'fixture@example.invalid',password:'fixture');
   final repository=SupabaseCommonPayrollPublicationRepository(client);
   final state=CommonPayrollPublicationState.parse(stateJson('company'),'company');final pending=CommonPayrollPublicationRequest(state,'daily','2026-10-01',requestId:'80000000-0000-0000-0000-000000000001');
   final future=repository.publish(pending);if(mode=='valid'){expect((await future).timelineVersion,1);}else{await expectLater(future,throwsStateError);}
   expect(bodies.single,pending.params);
  });
 }
 testWidgets('admin confirms explicit future month; previous month is unavailable',(tester) async {
  final repository=FakePublicationRepository();addTearDown(repository.changes.close);
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:CompanyCommonPayrollPublicationPanel(companyId:'company',repository:repository))));await tester.pumpAndSettle();
  await tester.tap(find.text('給与への適用月'));await tester.pumpAndSettle();
  expect(tester.widget<IconButton>(find.byKey(const ValueKey('common-publication-previous'))).onPressed,isNull);
  await tester.tap(find.byKey(const ValueKey('common-publication-next')));await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('common-publication-apply')));await tester.pumpAndSettle();expect(repository.requests,isEmpty);
  expect(find.textContaining('未保存の編集は含みません'),findsOneWidget);
  await tester.tap(find.text('適用する'));await tester.pumpAndSettle();expect(repository.requests.length,1);
  final now=DateTime.now().toUtc().add(const Duration(hours:9));final next=DateTime(now.year,now.month+1);
  expect(repository.requests.single.startsOn,'${next.year}-${next.month.toString().padLeft(2,'0')}-01');
 });
 testWidgets('same frame apply calls open one real dialog and publish one request',(tester) async {
  final repository=FakePublicationRepository();addTearDown(repository.changes.close);
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:CompanyCommonPayrollPublicationPanel(companyId:'company',repository:repository))));await tester.pumpAndSettle();
  await tester.tap(find.text('給与への適用月'));await tester.pumpAndSettle();
  final action=tester.widget<TextButton>(find.byKey(const ValueKey('common-publication-apply'))).onPressed!;
  action();action();await tester.pumpAndSettle();
  expect(find.byType(AlertDialog),findsOneWidget);expect(repository.requests,isEmpty);
  await tester.tap(find.text('適用する'));await tester.pumpAndSettle();expect(repository.requests.length,1);
 });
 testWidgets('company switch closes an old confirmation without publishing',(tester) async {
  final repository=FakePublicationRepository();addTearDown(repository.changes.close);
  Widget page(String company)=>MaterialApp(home:Scaffold(body:CompanyCommonPayrollPublicationPanel(key:const ValueKey('scope'),companyId:company,repository:repository)));
  await tester.pumpWidget(page('company-a'));await tester.pumpAndSettle();await tester.tap(find.text('給与への適用月'));await tester.pumpAndSettle();await tester.tap(find.byKey(const ValueKey('common-publication-apply')));await tester.pumpAndSettle();expect(find.byType(AlertDialog),findsOneWidget);
  await tester.pumpWidget(page('company-b'));await tester.pumpAndSettle();expect(find.byType(AlertDialog),findsNothing);expect(repository.requests,isEmpty);
 });
 testWidgets('unknown outcome reuses same request for result confirmation',(tester) async {
  final repository=FakePublicationRepository()..failOnce=true;addTearDown(repository.changes.close);
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:CompanyCommonPayrollPublicationPanel(companyId:'company',repository:repository))));await tester.pumpAndSettle();
  await tester.tap(find.text('給与への適用月'));await tester.pumpAndSettle();await tester.tap(find.byKey(const ValueKey('common-publication-apply')));await tester.pumpAndSettle();await tester.tap(find.text('適用する'));await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const ValueKey('common-publication-reconcile')));await tester.pumpAndSettle();await tester.tap(find.byKey(const ValueKey('common-publication-reconcile')));await tester.pumpAndSettle();
  expect(repository.requests.length,2);expect(repository.requests[0].requestId,repository.requests[1].requestId);expect(repository.requests[0].params,repository.requests[1].params);
 });
 testWidgets('viewer has no apply action',(tester) async {
  final repository=FakePublicationRepository()..canEdit=false;addTearDown(repository.changes.close);
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:CompanyCommonPayrollPublicationPanel(companyId:'company',repository:repository))));await tester.pumpAndSettle();await tester.tap(find.text('給与への適用月'));await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('common-publication-apply')),findsNothing);expect(repository.requests,isEmpty);
 });
 testWidgets('logout discards late publication reply',(tester) async {
  final repository=FakePublicationRepository()..held=Completer<CommonPayrollPublicationState>();addTearDown(repository.changes.close);
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:CompanyCommonPayrollPublicationPanel(companyId:'company',repository:repository))));await tester.pumpAndSettle();await tester.tap(find.text('給与への適用月'));await tester.pumpAndSettle();await tester.tap(find.byKey(const ValueKey('common-publication-apply')));await tester.pumpAndSettle();await tester.tap(find.text('適用する'));await tester.pump();
  repository.key=null;repository.changes.add(null);await tester.pump();repository.held!.complete(CommonPayrollPublicationState.parse(stateJson('company',version:1),'company'));await tester.pumpAndSettle();
  expect(find.text('ログイン状態が変わりました。この画面を開き直してください。'),findsOneWidget);expect(find.textContaining('適用月を登録し、対象の給与下書き'),findsNothing);
 });
}

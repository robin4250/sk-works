// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/payroll/resident_tax_reminder_repository.dart';
const company='00000000-0000-0000-0000-000000000100';
const other='00000000-0000-0000-0000-000000000200';
const actor='00000000-0000-0000-0000-000000000001';
const notification='00000000-0000-0000-0000-000000000900';
String session(String uid){
 String part(Object v)=>base64Url.encode(utf8.encode(jsonEncode(v)));
 return jsonEncode({'access_token':'${part({})}.${part({'sub':uid,'exp':DateTime.now().millisecondsSinceEpoch~/1000+3600})}.fixture',
 'refresh_token':'fixture','token_type':'bearer','expires_in':3600,'user':{'id':uid,'aud':'authenticated','created_at':'2026-01-01T00:00:00Z'}});
}
Map<String,dynamic> settings({String cid=company,bool edit=true})=>{'version':1,'company_id':cid,'enabled':false,'can_edit':edit,'updated_at':null,'dates':['05-01','05-25'],'timezone':'Asia/Tokyo'};
Map<String,dynamic> target({String cid=company})=>{'version':1,'company_id':cid,'tax_year':2026,'phase':'month_before','complete':false};
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 late SupabaseClient client;late SupabaseResidentTaxReminderRepository repository;
 late Future<http.Response> Function(http.Request) handle;
 setUp(() async {
  handle=(r) async=>http.Response(jsonEncode(settings()),200,request:r,headers:{'content-type':'application/json'});
  client=SupabaseClient('https://reminder.invalid','fixture',authOptions:const AuthClientOptions(autoRefreshToken:false),httpClient:MockClient((r)=>handle(r)));
  await client.auth.setInitialSession(session(actor));repository=SupabaseResidentTaxReminderRepository(client);
 });
 tearDown(()async{await client.dispose();});
 test('settings pins JWT and sends only explicit company',()async{
  handle=(r)async{expect(r.headers['Authorization'],startsWith('Bearer '));expect(jsonDecode(r.body),{'p_company_id':company});return http.Response(jsonEncode(settings()),200,request:r,headers:{'content-type':'application/json'});};
  expect((await repository.read(company)).enabled,false);
 });
 test('CAS save retains exact timestamp and requested company flag',()async{
  handle=(r)async{expect(jsonDecode(r.body),{'p_company_id':company,'p_enabled':true,'p_expected_updated_at':'2026-05-01T00:00:00.123456+00:00'});return http.Response(jsonEncode({...settings(),'enabled':true,'updated_at':'2026-05-02T00:00:00.123456+00:00'}),200,request:r,headers:{'content-type':'application/json'});};
  final value=ResidentTaxReminderSettings.parse({...settings(),'updated_at':'2026-05-01T00:00:00.123456+00:00'},company);
  expect((await repository.save(value,true)).enabled,true);
 });
 test('viewer save performs no HTTP',()async{
  handle=(r)async=>throw StateError('must not send');
  expect(()=>repository.save(ResidentTaxReminderSettings.parse(settings(edit:false),company),true),throwsStateError);
 });
 for(final code in ['PGRST202','42501','40001']){
  test('$code is surfaced without legacy fallback or retry',()async{
   var calls=0;handle=(r)async{calls++;return http.Response(jsonEncode({'code':code,'message':'fixture'}),403,request:r,headers:{'content-type':'application/json'});};
   await expectLater(repository.read(company),throwsA(isA<PostgrestException>()));expect(calls,1);
  });
 }
 test('notification validates saved company before workspace request',()async{
  var calls=0;handle=(r)async{calls++;return http.Response(jsonEncode(target(cid:other)),200,request:r,headers:{'content-type':'application/json'});};
  await expectLater(repository.target(notification,company),throwsFormatException);expect(calls,1);
 });
 test('notification blocks different current workspace before navigation',()async{
  handle=(r)async=>http.Response(jsonEncode(r.url.path.endsWith('payroll_workspace')?{'company_id':other,'permissions':{'view':true}}:target()),200,request:r,headers:{'content-type':'application/json'});
  await expectLater(repository.target(notification,company),throwsStateError);
 });
 test('notification authorized workspace retains year and completion',()async{
  handle=(r)async=>http.Response(jsonEncode(r.url.path.endsWith('payroll_workspace')?{'company_id':company,'permissions':{'view':true}}:{...target(),'complete':true}),200,request:r,headers:{'content-type':'application/json'});
  final result=await repository.target(notification,company);expect(result.fiscalYear,2026);expect(result.complete,true);
 });
 for(final next in [other,actor]){
  test('delayed response rejects ${next==actor?'same UID logout ABA':'different actor'}',()async{
   final started=Completer<void>(),release=Completer<void>();
   handle=(r)async{if(r.url.path.endsWith('/logout'))return http.Response('{}',200);started.complete();await release.future;return http.Response(jsonEncode(settings()),200,request:r,headers:{'content-type':'application/json'});};
   final result=repository.read(company);final expectation=expectLater(result,throwsStateError);await started.future;
   await client.auth.signOut(scope:SignOutScope.local);await client.auth.setInitialSession(session(next));await Future<void>.delayed(Duration.zero);release.complete();await expectation;
  });
 }
 test('settings rejects combined or reordered reminder dates and foreign company',(){
  for(final dates in [['05-01,05-25'],['05-25','05-01'],['05-01','05-25','05-25']]){
   expect(()=>ResidentTaxReminderSettings.parse({...settings(),'dates':dates},company),throwsFormatException);
  }
  expect(()=>ResidentTaxReminderSettings.parse(settings(cid:other),company),throwsFormatException);
 });
 test('malformed completion never counts as pending or complete',(){
  for(final value in [null,'yes',1]){expect(()=>ResidentTaxReminderTarget.parse({...target(),'complete':value},company),throwsFormatException);}
 });
}

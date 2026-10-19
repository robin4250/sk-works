// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/data/supabase_backend.dart';
import 'package:sk_works/features/auth/secondary_protected_page.dart';
import 'package:sk_works/features/notifications/app_notification_repository.dart';
import 'package:sk_works/features/notifications/attention_center_item.dart';
import 'package:sk_works/features/notifications/attention_center_repository.dart';
import 'package:sk_works/features/notifications/notifications_page.dart';
import 'package:sk_works/features/payroll/resident_tax_annual_page.dart';
import 'package:sk_works/features/payroll/resident_tax_reminder_repository.dart';
const url='https://resident-tax-notice-fixture.invalid',key='public_fixture';
const company='00000000-0000-0000-0000-000000000100',other='00000000-0000-0000-0000-000000000200',actor='00000000-0000-0000-0000-000000000001';
String id(int n)=>'00000000-0000-0000-0000-${n.toString().padLeft(12,'0')}';
String session(){
 String part(Object v)=>base64Url.encode(utf8.encode(jsonEncode(v)));
 return jsonEncode({'access_token':'${part({})}.${part({'sub':actor,'exp':4102444800})}.fixture','refresh_token':'fixture-only','token_type':'bearer','expires_in':3600,
 'user':{'id':actor,'aud':'authenticated','created_at':'2026-01-01T00:00:00Z'}});
}
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 if(!const bool.fromEnvironment('SKO_RESIDENT_NOTICE_FIXTURE')){
  test('resident notice HTTP requires fixed synthetic config',(){},skip:'Dedicated synthetic dart-defines only.');return;
 }
 final calls=<http.Request>[];var complete=false,foreign=false,missing=false;
 final rows=[for(final n in [900,901,902]){'id':id(n),'kind':'resident_tax_reminder','title':'住民税の切替準備','body':'通知書が届いたら確認・登録してください。','action_key':'payroll_settings','action_id':company,'read_at':null,'created_at':n==902?'2025-05-01T00:00:00Z':'2026-05-01T00:00:00Z'}];
 setUpAll(()async{
  expect(SupabaseBackendConfig.url,url);expect(SupabaseBackendConfig.publishableKey,key);
  SharedPreferences.setMockInitialValues({});
  await Supabase.initialize(url:url,publishableKey:key,debug:false,
   authOptions:const FlutterAuthClientOptions(autoRefreshToken:false,detectSessionInUri:false),
   httpClient:MockClient((request)async{
    expect(request.url.origin,url);calls.add(request);Object? value;
    switch(request.url.path){
     case '/rest/v1/app_notifications':expect(request.method,'GET');value=rows;
     case '/rest/v1/rpc/enqueue_due_invoice_approval_notifications':expect(request.method,'POST');value=null;
     case '/rest/v1/rpc/resident_tax_reminder_target':
      expect(request.method,'POST');
      if(missing)return http.Response(jsonEncode({'code':'PGRST202','message':'fixture missing'}),404,request:request,headers:{'content-type':'application/json'});
      final notification=(jsonDecode(request.body) as Map)['p_notification_id'];
      expect([id(900),id(901),id(902)],contains(notification));
      value={'version':1,'company_id':foreign?other:company,'tax_year':notification==id(902)?2025:2026,'phase':notification==id(901)?'week_before':'month_before','complete':notification==id(902)||complete};
     case '/rest/v1/rpc/payroll_workspace':expect(request.method,'POST');value={'company_id':company,'permissions':{'view':true}};
     default:throw StateError('Unexpected endpoint. Auth mutations, delivery, read writes and tax writes are forbidden.');
    }
    return http.Response(jsonEncode(value),200,request:request,headers:{'content-type':'application/json'});
   }));
  final original=Supabase.instance.client;await SupabaseBackend.initializeIfConfigured();expect(identical(SupabaseBackend.client,original),true);
  await original.auth.setInitialSession(session());
 });
 tearDownAll(()async{await Supabase.instance.dispose();});
 setUp((){calls.clear();complete=false;foreign=false;missing=false;});
 AttentionCenterSnapshot snapshot(List<AppNotificationRecord> items)=>AttentionCenterSnapshot(items.map((n)=>mapAttentionNotification(n)),now:DateTime(2026,5,25));
 test('real SDK notification read targets exact company/year and resolves without deleting history',()async{
  final repository=AppNotificationRepository.maybeCreate()!;var notifications=await repository.load();
  expect(notifications,hasLength(3));expect(snapshot(notifications).unresolvedCount,1);expect(snapshot(notifications).items,hasLength(2));
  final saved=await SupabaseResidentTaxReminderRepository(SupabaseBackend.client).target(id(900),company);
  final route=residentTaxReminderDestination(notifications.first,saved) as SecondaryProtectedPage;
  final page=route.child as ResidentTaxAnnualUpdatePage;expect(page.companyId,company);expect(page.fiscalYear,2026);expect(page.reminderPanel,isNotNull);
  complete=true;notifications=await repository.load();expect(notifications,hasLength(3));expect(notifications.every((n)=>!n.read),true);
  expect(snapshot(notifications).unresolvedCount,0);expect(snapshot(notifications).items.every((n)=>n.title.contains('更新確認済み')),true);
  complete=false;notifications=await repository.load();expect(snapshot(notifications).unresolvedCount,1);expect(notifications,hasLength(3));
  expect(calls.any((r)=>['PATCH','DELETE'].contains(r.method)),false);
 });
 test('wrong-company saved target remains visible history but cannot be pending or navigated',()async{
  foreign=true;final notifications=await AppNotificationRepository.maybeCreate()!.load();
  expect(notifications,hasLength(3));expect(snapshot(notifications).unresolvedCount,0);
  await expectLater(SupabaseResidentTaxReminderRepository(SupabaseBackend.client).target(id(900),company),throwsFormatException);
  expect(calls.where((r)=>r.url.path.endsWith('payroll_workspace')),isEmpty);
 });
 test('missing target backend does not guess completion, delete rows or use old individual route',()async{
  missing=true;final notifications=await AppNotificationRepository.maybeCreate()!.load();
  expect(notifications,hasLength(3));expect(snapshot(notifications).unresolvedCount,0);expect(notificationDestination(notifications.first),isNull);
  expect(calls.any((r)=>['PATCH','DELETE'].contains(r.method)),false);
 });
}

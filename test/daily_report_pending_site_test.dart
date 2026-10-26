// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/daily_reports/daily_report_month_page.dart';
import 'package:sk_works/features/daily_reports/daily_report_month_repository.dart';
import 'package:sk_works/features/daily_reports/daily_report_repository.dart';

const actorId='00000000-0000-4000-8000-000000000001';
const companyId='00000000-0000-4000-8000-000000000002';
String id(int n)=>'00000000-0000-4000-8000-${n.toString().padLeft(12,'0')}';
DailyReportMonthEntry entry(String report,DateTime date,{String site='site-a',String name='現場A',String status='draft',bool reporter=true,bool supervisor=false})=>DailyReportMonthEntry(
 id:report,date:date,name:name,siteId:site,status:status,reporterSigned:reporter,supervisorSigned:supervisor);
class FixtureReports extends DailyReportMonthRepository{
 FixtureReports(SupabaseClient client):super(client, DailyReportRepository.forTesting(client));
 bool invalid=false,fail=false;int pendingReads=0;
 @override String get actor=>actorId;
 @override void checkActor(String user){if(invalid||user!=actorId)throw StateError('actor changed');}
 @override Future<List<DailyReportMonthEntry>> list(DateTime month,{String? workerId})async=>[
  entry('saved',DateTime(2026,10,26),status:'signed'),entry('pending',DateTime(2026,10,25))];
 @override Future<DailyReportPendingResult> listPending({String? workerId})async{
  pendingReads++;if(fail)throw StateError('read failed');
  return DailyReportPendingResult([entry('old-a',DateTime(2025,1,2)),entry('old-b',DateTime(2026,3,4)),entry('other',DateTime(2024,2,1),site:'site-b',name:'現場B')]);
 }
}
class ReadReports extends DailyReportMonthRepository{
 ReadReports(SupabaseClient client):super(client, DailyReportRepository.forTesting(client));
 @override String get actor=>actorId;
 @override void checkActor(String user){if(user!=actorId)throw StateError('actor changed');}
}
void main(){
 final clients=<SupabaseClient>[];
 tearDown(() async {debugPrint('DIAG teardown start');for(final client in clients){await client.dispose();}clients.clear();debugPrint('DIAG teardown end');});
 setUp((){final previous=SharedPreferencesAsyncPlatform.instance;SharedPreferencesAsyncPlatform.instance=InMemorySharedPreferencesAsync.empty();addTearDown(()=>SharedPreferencesAsyncPlatform.instance=previous);});
 test('saved, supervisor pending, unfinished and finalization pending remain distinct',(){
  expect(entry('s',DateTime(2026),status:'signed').saveState,DailyReportSaveState.saved);
  expect(entry('v',DateTime(2026),status:'completed').saveState,DailyReportSaveState.saved);
  expect(entry('p',DateTime(2026)).saveState,DailyReportSaveState.supervisorPending);
  expect(entry('f',DateTime(2026),supervisor:true).saveState,DailyReportSaveState.finalizationPending);
  expect(entry('i',DateTime(2026),reporter:false).saveState,DailyReportSaveState.inputPending);
  expect(entry('unknown',DateTime(2026),status:'unknown').saveState,DailyReportSaveState.inputPending);
 });
 testWidgets('red pending all-month groups open saved identity without choosing a day',(tester)async{
  tester.view.physicalSize=const Size(390,1000);tester.view.devicePixelRatio=1;addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  final client=SupabaseClient('https://example.invalid','fixture-public',authOptions:const AuthClientOptions(autoRefreshToken:false));clients.add(client);
  final repo=FixtureReports(client);String? opened;
  debugPrint('DIAG pumpWidget begin');await tester.pumpWidget(MaterialApp(home:DailyReportMonthPage(initialMonth:DateTime(2026,10),repositoryForTesting:repo,
   pendingBuilderForTesting:(e){opened=e.id;return Scaffold(appBar:AppBar(),body:Text('既存日報 ${e.id}'));})));
  debugPrint('DIAG settle begin');await tester.pumpAndSettle(const Duration(milliseconds:100), EnginePhase.sendSemanticsUpdate, const Duration(seconds:3));debugPrint('DIAG settle end');expect(find.text('保存済み 1件'),findsOneWidget);expect(find.text('サイン待ち 1件'),findsNothing);
  await tester.tap(find.byKey(const ValueKey('daily-report-pending-filter')));debugPrint('DIAG settle begin');await tester.pumpAndSettle(const Duration(milliseconds:100), EnginePhase.sendSemanticsUpdate, const Duration(seconds:3));debugPrint('DIAG settle end');
  expect(find.text('責任者サイン待ち 3件'),findsOneWidget);expect(find.text('すべての月・現場別'),findsOneWidget);
  expect(find.byKey(const ValueKey('daily-report-pending-site-site:site-a')),findsOneWidget);
  expect(find.byKey(const ValueKey('daily-report-pending-site-site:site-b')),findsOneWidget);
  expect(find.textContaining('2025-01-02'),findsOneWidget);expect(find.textContaining('2024-02-01'),findsOneWidget);
  final text=tester.widget<Text>(find.text('責任者サイン待ち 3件'));expect(text.style!.color,Colors.red.shade900);
  await tester.tap(find.descendant(of:find.byKey(const ValueKey('daily-report-pending-entry-old-a')),matching:find.text('サイン')));debugPrint('DIAG settle begin');await tester.pumpAndSettle(const Duration(milliseconds:100), EnginePhase.sendSemanticsUpdate, const Duration(seconds:3));debugPrint('DIAG settle end');
  expect(opened,'old-a');expect(find.text('既存日報 old-a'),findsOneWidget);
  await tester.pageBack();debugPrint('DIAG settle begin');await tester.pumpAndSettle(const Duration(milliseconds:100), EnginePhase.sendSemanticsUpdate, const Duration(seconds:3));debugPrint('DIAG settle end');expect(repo.pendingReads,2);expect(tester.takeException(),isNull);
 }, timeout: const Timeout(Duration(seconds: 30)));
 testWidgets('pending error is never presented as an empty successful list',(tester)async{
  final client=SupabaseClient('https://example.invalid','fixture-public',authOptions:const AuthClientOptions(autoRefreshToken:false));clients.add(client);final repo=FixtureReports(client)..fail=true;
  debugPrint('DIAG pumpWidget begin');await tester.pumpWidget(MaterialApp(home:DailyReportMonthPage(repositoryForTesting:repo)));debugPrint('DIAG settle begin');await tester.pumpAndSettle(const Duration(milliseconds:100), EnginePhase.sendSemanticsUpdate, const Duration(seconds:3));debugPrint('DIAG settle end');
  await tester.tap(find.byKey(const ValueKey('daily-report-pending-filter')));debugPrint('DIAG settle begin');await tester.pumpAndSettle(const Duration(milliseconds:100), EnginePhase.sendSemanticsUpdate, const Duration(seconds:3));debugPrint('DIAG settle end');
  expect(find.text('サイン待ちの日報を取得できません。再読み込みしてください。'),findsOneWidget);expect(find.text('責任者サイン待ちの日報はありません。'),findsNothing);
 });
 for(final visitAvailable in [true,false]){
 test('pending metadata pagination spans years and visit absence preserves ordinary reports $visitAvailable',()async{
  var reads=0;final requests=<Uri>[];
  final client=SupabaseClient('https://example.invalid','fixture-public',authOptions:const AuthClientOptions(autoRefreshToken:false),httpClient:MockClient((request)async{
   requests.add(request.url);Object result;
   if(request.url.path.endsWith('/daily_reports')){
    expect(request.url.queryParameters['status'],'eq.draft');expect(request.url.queryParameters['representative_signature_json'],'not.is.null');
    expect(request.url.queryParameters['select'],isNot(contains('signature_json')));
    if(reads++==0){result=[for(var n=10;n<210;n++){'id':id(n),'report_date':'2024-01-01','status':'draft','work_description':'保存済作業','site_id':id(3),'route_assignment_id':null,'sites':{'name':'現場A'}}];}
    else{expect(request.url.queryParameters['or'],contains(id(209)));result=[{'id':id(210),'report_date':'2025-02-02','status':'draft','work_description':'保存済作業','site_id':id(3),'route_assignment_id':null,'sites':{'name':'現場A'}}];}
   }else if(request.url.path.endsWith('/company_members')){result=[{'company_id':companyId}];}
   else if(request.url.path.endsWith('/rpc/list_pending_route_visit_reports')){
    final params=jsonDecode(request.body) as Map;expect(params['p_company_id'],companyId);expect(params['p_after_id'],isNull);
    if(!visitAvailable)return http.Response(jsonEncode({'code':'PGRST202','message':'missing'}),404,headers:{'content-type':'application/json'},request:request);
    result={'actor_id':actorId,'company_id':companyId,'entries':[{'id':id(300),'company_id':companyId,'report_date':'2023-01-01','status':'reporter_signed','reporter_signed':true,'supervisor_signed':false,'site_id':id(4),'site_name':'別訪問現場','source_clock_in_id':id(301),'route_assignment_id':id(302),'route_stop_id':id(303),'start_capture_id':id(304),'end_capture_id':id(305)}]};
   }else{throw StateError('unexpected ${request.url}');}
   return http.Response(jsonEncode(result),200,headers:{'content-type':'application/json'},request:request);
  }));clients.add(client);
  final result=await ReadReports(client).listPending();expect(reads,2);expect(result.entries.length,visitAvailable?202:201);
  expect(result.entries.where((e)=>e.isVisit).length,visitAvailable?1:0);expect(result.visitWarning,visitAvailable?isNull:isNotNull);
  expect(result.entries.every((e)=>e.saveState==DailyReportSaveState.supervisorPending),isTrue);
  expect(requests.where((u)=>u.path.endsWith('/daily_reports')).every((u)=>!u.queryParameters.containsKey('report_date')),isTrue);
 });}
}

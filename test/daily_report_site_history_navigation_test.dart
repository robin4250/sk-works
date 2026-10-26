// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/daily_reports/daily_report_month_repository.dart';
import 'package:sk_works/features/daily_reports/daily_report_repository.dart';
import 'package:sk_works/features/daily_reports/daily_report_saved_preview_pager.dart';

const actor='00000000-0000-4000-8000-000000000001';
const site='00000000-0000-4000-8000-000000000002';
String rid(int n)=>'00000000-0000-4000-8000-${n.toString().padLeft(12,'0')}';
DailyReportMonthEntry row(String id,DateTime date,{int hour=0,bool pending=false})=>DailyReportMonthEntry(
 id:id,date:date,createdAt:DateTime.utc(date.year,date.month,date.day,hour),name:'現場A',siteId:site,
 status:pending?'draft':'signed',reporterSigned:pending);
class History extends DailyReportMonthRepository{
 History(SupabaseClient client,{this.pending=false}):super(client,DailyReportRepository.forTesting(client));
 final bool pending;bool fail=false,changed=false;final opened=<String>[];
 List<DailyReportMonthEntry> get all=>[row('old',DateTime(2024,1,2),pending:pending),
  row('anchor',DateTime(2026,10,26),hour:1,pending:pending),row('same-day',DateTime(2026,10,26),hour:2,pending:pending),
  row('new',DateTime(2027,2,3),pending:pending)];
 @override String get actor=> '00000000-0000-4000-8000-000000000001';
 @override void checkActor(String a){if(a!=actor)throw StateError('actor');}
 @override Future<DailyReportSiteHistoryResult> listSiteHistory(DailyReportMonthEntry anchor,{String? workerId})async{
  if(fail)throw StateError('network');return DailyReportSiteHistoryResult(all);
 }
 @override Future<DailyReportMonthDocument> loadOne(DailyReportMonthEntry e,{required String expectedActor})async{
  checkActor(expectedActor);opened.add(e.id);return DailyReportMonthDocument(DailyReportRecord(
   id:e.id,siteId:site,siteName:'現場A',date:e.date,status:changed?'signed':e.status,workDescription:e.id,workers:const [],
   reporterSignatureJson:pending?{'strokes':[[{'x':0.1,'y':0.2}]]}:null),const []);
 }
}
void fastTestWidgets(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(name, body, timeout: const Timeout(Duration(seconds: 30)));
void main(){
 final clients=<SupabaseClient>[];
 tearDown(() async {debugPrint('DIAG teardown start');for(final client in clients){await client.dispose();}clients.clear();debugPrint('DIAG teardown end');});
 for(final pending in [false,true]){
 for(final scale in [1.0,1.5]) {
 fastTestWidgets('large controls navigate year boundaries and same-day IDs in one category $pending $scale',(tester)async{
  tester.view.physicalSize=const Size(390,800);tester.view.devicePixelRatio=1;addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  final client=SupabaseClient('https://example.invalid','fixture-public',authOptions:const AuthClientOptions(autoRefreshToken:false));clients.add(client);
  final history=History(client,pending:pending);final anchor=history.all[1];
  debugPrint('DIAG pumpWidget begin');await tester.pumpWidget(MaterialApp(builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:TextScaler.linear(scale)),child:child!), home:DailyReportSavedPreviewPager(repository:history,actor:actor,
   entries:[anchor],initialEntryId:anchor.id,allPeriodNavigation:true,
   previewBuilderForTesting:(doc)=>Scaffold(body:Center(child:Text('report:${doc.report.id}'))))));
  debugPrint('DIAG settle begin');await tester.pumpAndSettle(const Duration(milliseconds:100), EnginePhase.sendSemanticsUpdate, const Duration(seconds:3));debugPrint('DIAG settle end');expect(find.text('2 / 4件'),findsOneWidget);expect(find.text(pending?'サイン待ち':'保存済み'),findsOneWidget);
  final previous=find.byKey(const ValueKey('daily-report-previous')),next=find.byKey(const ValueKey('daily-report-next'));
  expect(tester.getSize(previous).height,greaterThanOrEqualTo(48));expect(tester.getSize(next).width,greaterThanOrEqualTo(48));
  await tester.tap(previous);debugPrint('DIAG settle begin');await tester.pumpAndSettle(const Duration(milliseconds:100), EnginePhase.sendSemanticsUpdate, const Duration(seconds:3));debugPrint('DIAG settle end');expect(find.text('2024年'),findsOneWidget);expect(find.text('1月2日'),findsOneWidget);
  expect(tester.widget<OutlinedButton>(previous).onPressed,isNull);expect(find.text('最も古い日報'),findsOneWidget);
  await tester.tap(next);debugPrint('DIAG settle begin');await tester.pumpAndSettle(const Duration(milliseconds:100), EnginePhase.sendSemanticsUpdate, const Duration(seconds:3));debugPrint('DIAG settle end');await tester.tap(next);debugPrint('DIAG settle begin');await tester.pumpAndSettle(const Duration(milliseconds:100), EnginePhase.sendSemanticsUpdate, const Duration(seconds:3));debugPrint('DIAG settle end');expect(find.text('report:same-day'),findsOneWidget);
  await tester.tap(next);debugPrint('DIAG settle begin');await tester.pumpAndSettle(const Duration(milliseconds:100), EnginePhase.sendSemanticsUpdate, const Duration(seconds:3));debugPrint('DIAG settle end');expect(find.text('2027年'),findsOneWidget);expect(find.text('4 / 4件'),findsOneWidget);
  expect(tester.widget<OutlinedButton>(next).onPressed,isNull);expect(find.text('最も新しい日報'),findsOneWidget);
  expect(history.opened,['anchor','old','anchor','same-day','new']);expect(tester.takeException(),isNull);
 });}}
 fastTestWidgets('unavailable all-period history does not claim oldest or newest',(tester)async{
  final client=SupabaseClient('https://example.invalid','fixture-public',authOptions:const AuthClientOptions(autoRefreshToken:false));clients.add(client);
  final history=History(client)..fail=true;final anchor=history.all[1];
  debugPrint('DIAG pumpWidget begin');await tester.pumpWidget(MaterialApp(home:DailyReportSavedPreviewPager(repository:history,actor:actor,entries:[anchor],initialEntryId:anchor.id,allPeriodNavigation:true,
   previewBuilderForTesting:(doc)=>Scaffold(body:Text('report:${doc.report.id}')))));
  debugPrint('DIAG settle begin');await tester.pumpAndSettle(const Duration(milliseconds:100), EnginePhase.sendSemanticsUpdate, const Duration(seconds:3));debugPrint('DIAG settle end');expect(find.text('report:anchor'),findsOneWidget);expect(find.textContaining('全期間を取得できません'),findsOneWidget);
  expect(find.text('最も新しい日報'),findsNothing);expect(find.text('最も古い日報'),findsNothing);expect(find.text('範囲未確認'),findsNWidgets(2));
 });
 fastTestWidgets('a completed report cannot remain in pending preview after server state changes',(tester)async{
  final client=SupabaseClient('https://example.invalid','fixture-public',authOptions:const AuthClientOptions(autoRefreshToken:false));clients.add(client);
  final history=History(client,pending:true)..changed=true;final anchor=history.all[1];
  debugPrint('DIAG pumpWidget begin');await tester.pumpWidget(MaterialApp(home:DailyReportSavedPreviewPager(repository:history,actor:actor,entries:[anchor],initialEntryId:anchor.id,allPeriodNavigation:true,
   previewBuilderForTesting:(doc)=>Scaffold(body:Text('report:${doc.report.id}')))));
  debugPrint('DIAG settle begin');await tester.pumpAndSettle(const Duration(milliseconds:100), EnginePhase.sendSemanticsUpdate, const Duration(seconds:3));debugPrint('DIAG settle end');expect(find.textContaining('保存状態が変わりました'),findsOneWidget);expect(find.text('report:anchor'),findsNothing);
 });
 fastTestWidgets('zoomed PDF pan preserves current report while large arrow remains available',(tester)async{
  final client=SupabaseClient('https://example.invalid','fixture-public',authOptions:const AuthClientOptions(autoRefreshToken:false));clients.add(client);
  final history=History(client);final anchor=history.all[1];
  debugPrint('DIAG pumpWidget begin');await tester.pumpWidget(MaterialApp(home:DailyReportSavedPreviewPager(repository:history,actor:actor,entries:[anchor],initialEntryId:anchor.id,allPeriodNavigation:true,
   previewWithZoomBuilderForTesting:(doc,zoom)=>Scaffold(body:Column(children:[Text('report:${doc.report.id}'),TextButton(onPressed:()=>zoom(true),child:const Text('拡大'))])))));
  debugPrint('DIAG settle begin');await tester.pumpAndSettle(const Duration(milliseconds:100), EnginePhase.sendSemanticsUpdate, const Duration(seconds:3));debugPrint('DIAG settle end');await tester.tap(find.text('拡大'));debugPrint('DIAG settle begin');await tester.pumpAndSettle(const Duration(milliseconds:100), EnginePhase.sendSemanticsUpdate, const Duration(seconds:3));debugPrint('DIAG settle end');
  await tester.fling(find.byKey(const ValueKey('daily-report-preview-swipe')),const Offset(250,0),800);debugPrint('DIAG settle begin');await tester.pumpAndSettle(const Duration(milliseconds:100), EnginePhase.sendSemanticsUpdate, const Duration(seconds:3));debugPrint('DIAG settle end');expect(history.opened,['anchor']);
  await tester.tap(find.byKey(const ValueKey('daily-report-next')));debugPrint('DIAG settle begin');await tester.pumpAndSettle(const Duration(milliseconds:100), EnginePhase.sendSemanticsUpdate, const Duration(seconds:3));debugPrint('DIAG settle end');expect(history.opened,['anchor','same-day']);expect(tester.takeException(),isNull);
 });
 test('RLS metadata history uses selected site/status and keyset beyond one month',()async{
  var reads=0;final client=SupabaseClient('https://example.invalid','fixture-public',authOptions:const AuthClientOptions(autoRefreshToken:false),httpClient:MockClient((request)async{
   Object body;
   if(request.url.path.endsWith('/daily_reports')){
    expect(request.url.queryParameters['site_id'],'eq.$site');expect(request.url.queryParameters['status'],'in.("signed","completed")');
    expect(request.url.queryParameters['select'],isNot(contains('signature_json')));expect(request.url.queryParameters.containsKey('report_date'),isFalse);
    body=reads++==0?[for(var n=10;n<210;n++){'id':rid(n),'report_date':'2024-01-01','created_at':'2024-01-01T00:00:00Z','site_id':site,'status':'signed','sites':{'name':'現場A'}}]
     :[{'id':rid(210),'report_date':'2027-01-01','site_id':site,'status':'signed','sites':{'name':'現場A'}}];
    if(reads==2)expect(request.url.queryParameters['or'],contains(rid(209)));
   }else if(request.url.path.endsWith('/company_members')){body=[];}else{throw StateError('unexpected request');}
   return http.Response(jsonEncode(body),200,headers:{'content-type':'application/json'},request:request);
  }));clients.add(client);
  final result=await _Reads(client).listSiteHistory(row('anchor',DateTime(2026,10,26)));expect(reads,2);expect(result.complete,isTrue);expect(result.entries.length,201);expect(result.entries.last.date.year,2027);
 });
}
class _Reads extends DailyReportMonthRepository{
 _Reads(SupabaseClient c):super(c,DailyReportRepository.forTesting(c));
 @override String get actor=>'00000000-0000-4000-8000-000000000001';
 @override void checkActor(String value){if(value!=actor)throw StateError('actor');}
}

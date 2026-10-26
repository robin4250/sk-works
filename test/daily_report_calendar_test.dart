// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:sk_works/features/daily_reports/daily_report_calendar_model.dart';
import 'package:sk_works/features/daily_reports/daily_report_month_page.dart';
import 'package:sk_works/features/daily_reports/daily_report_month_repository.dart';
import 'package:sk_works/features/daily_reports/daily_report_repository.dart';
import 'package:sk_works/features/daily_reports/daily_report_page.dart';
import 'package:sk_works/features/daily_reports/daily_report_saved_preview_pager.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/international/language_controller.dart';
import 'package:sk_works/international/languages/en/english_language_pack.dart';

DailyReportMonthEntry entry(String id, int day, int hour, {String site = 'site-a', String name = '現場A'}) =>
  DailyReportMonthEntry(id: id, date: DateTime(2026,10,day), createdAt: DateTime.utc(2026,10,day,hour),
    name: name, status: 'signed', siteId: site);

class Reports extends DailyReportMonthRepository {
  Reports(SupabaseClient client) : super(client, DailyReportRepository.forTesting(client));
  final opened = <String>[];
  final requestedMonths = <int>[];
  bool changed = false;
  bool extraOld = false;
  final classified = <String>[];
  @override
  String get actor => 'actor';
  @override
  void checkActor(String actor) { if (changed || actor != this.actor) throw StateError('Actor changed'); }
  @override
  Future<List<DailyReportMonthEntry>> list(DateTime month, {String? workerId}) async {
    requestedMonths.add(month.month);
    if (month.month != 10) return [];
    return [if (extraOld) entry('older',12,0), entry('new',12,2), entry('old',12,1), entry('tomorrow',13,1),
      entry('other',12,1,site:'site-b',name:'現場B')];
  }
  @override
  Future<DailyReportSiteHistoryResult> listSiteHistory(DailyReportMonthEntry anchor, {String? workerId}) async =>
    DailyReportSiteHistoryResult((await list(anchor.date)).where((entry) =>
      dailyReportDestinationKey(entry) == dailyReportDestinationKey(anchor) && entry.saveState == anchor.saveState).toList());
  @override
  Future<bool> hasPhotos(DailyReportMonthEntry entry, {required String expectedActor}) async {
    checkActor(expectedActor);
    classified.add(entry.id);
    return entry.id == 'new';
  }
  @override
  Future<DailyReportMonthDocument> loadOne(DailyReportMonthEntry entry, {required String expectedActor}) async {
    checkActor(expectedActor);
    opened.add(entry.id);
    return DailyReportMonthDocument(DailyReportRecord(id: entry.id, date: entry.date, siteId: entry.siteId,
      siteName: entry.name, workDescription: '作業:${entry.id}', status:'signed', workers:[]), const []);
  }
}

class SavedReports extends DailyReportRepository {
  SavedReports(super.client) : super.forTesting();
  String? requestedId;
  bool missing = false;
  @override
  Future<List<DailyReportSiteGroup>> loadClockedInGroups(DateTime date) async =>
    throw StateError('Editing a saved ID must not select current attendance');
  @override
  Future<DailyReportRecord?> loadReport({required DateTime date, String? siteId,
    String? routeAssignmentId, String? vehicleClockInAnchorId, String? reportId}) async {
    requestedId=reportId;
    return missing ? null : DailyReportRecord(id:reportId!,date:date,siteId:siteId,
      siteName:'保存済み現場',workDescription:'選択した古い日報の作業',status:'draft',workers:[]);
  }
  @override
  Future<List<DailyReportEvidenceRecord>> loadAttendanceEvidence({String? reportId,
    required DateTime date,String? siteId,String? routeAssignmentId}) async => [];
}

void main() {
  late SupabaseClient client;
  setUp(() {
    final previous=SharedPreferencesAsyncPlatform.instance;
    SharedPreferencesAsyncPlatform.instance=InMemorySharedPreferencesAsync.empty();
    addTearDown(()=>SharedPreferencesAsyncPlatform.instance=previous);
    client = SupabaseClient('https://example.invalid','synthetic-public',
    authOptions:const AuthClientOptions(autoRefreshToken:false)); });
  tearDown(() async { await client.dispose(); });

  test('saved IDs sort oldest first and next-day skips other records on the same day', () {
    final reports = chronologicalDailyReports([entry('new',12,2),entry('tomorrow',13,1),entry('old',12,1)]);
    expect(reports.map((e)=>e.id),['old','new','tomorrow']);
    expect(nextDailyReportDay(reports,0),2);
    expect(nextDailyReportDay(reports,1),2);
    expect(nextDailyReportDay(reports,2),isNull);
  });

  testWidgets('month entrance lists sites, calendar classifies each saved report once, month arrows stay monthly', (tester) async {
    tester.view.physicalSize = const Size(320,720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final reports=Reports(client);
    await tester.pumpWidget(MaterialApp(builder:(context,child)=>MediaQuery(
      data:MediaQuery.of(context).copyWith(textScaler:const TextScaler.linear(1.3)), child:child!),
      home:DailyReportMonthPage(initialMonth:DateTime(2026,10),repositoryForTesting:reports,
        previewBuilderForTesting:(doc)=>Scaffold(appBar:AppBar(title:Text(doc.report.id)),body:Text(doc.report.workDescription)))));
    await tester.pumpAndSettle();
    expect(find.text('現場A'),findsOneWidget); expect(find.text('現場B'),findsOneWidget);
    expect(find.text('月まとめて共有・保存'),findsOneWidget);
    await tester.tap(find.text('現場A')); await tester.pumpAndSettle();
    final noPhotos=find.byKey(const ValueKey('daily-report-day-12-no-photos'));
    await tester.scrollUntilVisible(noPhotos,500); await tester.pumpAndSettle();
    expect(find.descendant(of:noPhotos,matching:find.text('写真無し 1件')),findsOneWidget);
    expect(find.byKey(const ValueKey('daily-report-day-12-photos')),findsOneWidget);
    await tester.tap(noPhotos); await tester.pumpAndSettle();
    expect(find.text('作業:old'),findsOneWidget);
    await tester.pageBack(); await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('次の月')); await tester.pumpAndSettle();
    expect(find.text('2026年11月'),findsOneWidget);
    expect(reports.requestedMonths.last,11);
    expect(tester.takeException(),isNull);
  });

  testWidgets('calendar dates use blue Saturdays and red Sundays and Japanese holidays', (tester) async {
    final reports = Reports(client);
    final theme = ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue));
    await tester.pumpWidget(MaterialApp(theme: theme,
      home: DailyReportMonthPage(initialMonth: DateTime(2026, 10), repositoryForTesting: reports)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('現場A'));
    await tester.pumpAndSettle();
    Future<Color?> dateColor(int day) async {
      final label = find.byKey(ValueKey('daily-report-date-label-$day'));
      await tester.scrollUntilVisible(label, 200);
      await tester.pumpAndSettle();
      return tester.widget<Text>(label).style?.color;
    }
    expect(await dateColor(3), Colors.blue.shade700);
    expect(await dateColor(4), theme.colorScheme.error);
    expect(await dateColor(5), isNull);
    // Sports Day is a Monday, so this checks the holiday rule separately.
    expect(await dateColor(12), theme.colorScheme.error);
    expect(find.byKey(const ValueKey('daily-report-day-12-no-photos')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('same-day photo groups keep each report ID selectable in creation order', (tester) async {
    final reports=Reports(client)..extraOld=true;
    await tester.pumpWidget(MaterialApp(home:DailyReportMonthPage(initialMonth:DateTime(2026,10),
      repositoryForTesting:reports,previewBuilderForTesting:(doc)=>Scaffold(appBar:AppBar(title:Text(doc.report.id)),
        body:Text(doc.report.workDescription)))));
    await tester.pumpAndSettle(); await tester.tap(find.text('現場A')); await tester.pumpAndSettle();
    final button=find.byKey(const ValueKey('daily-report-day-12-no-photos'));
    await tester.scrollUntilVisible(button,400); await tester.pumpAndSettle();
    expect(find.descendant(of:button,matching:find.text('写真無し 2件')),findsOneWidget);
    expect(reports.classified.where((id)=>id=='old').length,1);
    await tester.tap(button); await tester.pumpAndSettle();
    final older=find.byKey(const ValueKey('daily-report-select-older'));
    final old=find.byKey(const ValueKey('daily-report-select-old'));
    expect(tester.getTopLeft(older).dy,lessThan(tester.getTopLeft(old).dy));
    await tester.tap(old); await tester.pumpAndSettle();
    expect(find.text('作業:old'),findsOneWidget);
    expect(reports.opened,['old']);
    expect(tester.takeException(),isNull);
  });

  testWidgets('English month header and calendar fit 320px with enlarged text', (tester) async {
    final before=SkoLanguageController.pack.value;
    SkoLanguageController.pack.value=englishLanguagePack;
    addTearDown(()=>SkoLanguageController.pack.value=before);
    tester.view.physicalSize=const Size(320,720); tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final reports=Reports(client);
    await tester.pumpWidget(MaterialApp(builder:(context,child)=>MediaQuery(
      data:MediaQuery.of(context).copyWith(textScaler:const TextScaler.linear(1.6)),child:child!),
      home:DailyReportMonthPage(initialMonth:DateTime(2026,10),repositoryForTesting:reports)));
    await tester.pumpAndSettle();
    expect(find.text('Share / save month'),findsOneWidget);
    await tester.tap(find.text('現場A')); await tester.pumpAndSettle();
    final noPhotos=find.byKey(const ValueKey('daily-report-day-12-no-photos'));
    await tester.scrollUntilVisible(noPhotos,400); await tester.pumpAndSettle();
    expect(find.descendant(of:noPhotos,matching:find.text('Without photos: 1')),findsOneWidget);
    expect(tester.takeException(),isNull);
  });

  testWidgets('failed photo metadata is not classified as a report without photos', (tester) async {
    final reports=Reports(client);
    await tester.pumpWidget(MaterialApp(home:DailyReportMonthPage(initialMonth:DateTime(2026,10),
      repositoryForTesting:reports)));
    await tester.pumpAndSettle(); reports.changed=true;
    await tester.tap(find.text('現場A')); await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const ValueKey('daily-report-date-12')),400); await tester.pumpAndSettle();
    expect(find.text('写真情報を再読み込み'),findsWidgets);
    expect(find.byKey(const ValueKey('daily-report-day-12-no-photos')),findsNothing);
    expect(find.byKey(const ValueKey('daily-report-day-12-photos')),findsNothing);
    expect(tester.takeException(),isNull);
  });

  testWidgets('editing an old saved ID reads that ID and cannot create a replacement when it is missing', (tester) async {
    final reports=SavedReports(client);
    await tester.pumpWidget(MaterialApp(home:DailyReportPage(initialDate:DateTime(2026,10,12),
      initialSiteId:'site-a',initialReportId:'older-id',repositoryForTesting:reports)));
    await tester.pumpAndSettle();
    expect(reports.requestedId,'older-id');
    expect(find.text('選択した古い日報の作業'),findsOneWidget);
    expect(tester.takeException(),isNull);
    reports.missing=true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(MaterialApp(home:DailyReportPage(initialDate:DateTime(2026,10,12),
      initialSiteId:'site-a',initialReportId:'older-id',repositoryForTesting:reports)));
    await tester.pumpAndSettle();
    expect(find.textContaining('選んだ保存済み日報を確認できません。日報一覧を再読み込みしてください。'),findsOneWidget);
    expect(find.byType(TextField),findsNothing);
    expect(tester.takeException(),isNull);
  });

  testWidgets('slow deliberate drags navigate while zoomed PDF pan keeps the same report', (tester) async {
    final reports=Reports(client);
    final controller=TransformationController();
    addTearDown(controller.dispose);
    final entries=[entry('old',12,1),entry('tomorrow',13,1)];
    await tester.pumpWidget(MaterialApp(home:DailyReportSavedPreviewPager(repository:reports,actor:'actor',
      entries:entries,initialEntryId:'old',previewWithZoomBuilderForTesting:(doc,onZoomChanged)=>Scaffold(
        appBar:AppBar(actions:[
          IconButton(tooltip:'zoom in',onPressed:(){
            controller.value=Matrix4.diagonal3Values(2,2,1); onZoomChanged(true);
          },icon:const Icon(Icons.zoom_in)),
          IconButton(tooltip:'zoom out',onPressed:()=>onZoomChanged(false),icon:const Icon(Icons.zoom_out)),
        ]),
        body:InteractiveViewer(key:const ValueKey('zoomed-report-fixture'),
          transformationController:controller,constrained:false,
          child:SizedBox(width:1200,height:800,child:Text(doc.report.id)))))));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('zoom in')); await tester.pumpAndSettle();
    final before=controller.value.clone();
    await tester.timedDrag(find.byKey(const ValueKey('zoomed-report-fixture')),const Offset(-100,0),const Duration(seconds:2));
    await tester.pumpAndSettle();
    expect(controller.value == before,isFalse);
    expect(reports.opened,['old']);
    await tester.tap(find.byTooltip('zoom out')); await tester.pumpAndSettle();
    // Use the navigation strip, which remains separate from the PDF's pan area.
    final surface=find.byKey(const ValueKey('daily-report-preview-swipe'));
    final start=tester.getBottomLeft(surface)+const Offset(300,-30);
    final gesture=await tester.startGesture(start);
    await gesture.moveBy(const Offset(30,0),timeStamp:const Duration(seconds:1));
    await gesture.moveBy(const Offset(80,0),timeStamp:const Duration(seconds:2));
    await gesture.up(timeStamp:const Duration(seconds:3));
    await tester.pumpAndSettle();
    expect(reports.opened,['old','tomorrow']);
    expect(tester.takeException(),isNull);
  });

  testWidgets('right swipe opens next same-day ID before a newer day', (tester) async {
    final reports=Reports(client);
    final entries=[entry('new',12,2),entry('old',12,1),entry('tomorrow',13,1)];
    await tester.pumpWidget(MaterialApp(home:DailyReportSavedPreviewPager(repository:reports,actor:'actor',
      entries:entries, initialEntryId:'new',previewBuilderForTesting:(doc)=>Scaffold(body:Center(child:Text(doc.report.id))))));
    await tester.pumpAndSettle();
    await tester.fling(find.byKey(const ValueKey('daily-report-preview-swipe')),const Offset(-350,0),1000);
    await tester.pumpAndSettle(); expect(find.text('old'),findsOneWidget);
    await tester.fling(find.byKey(const ValueKey('daily-report-preview-swipe')),const Offset(350,0),1000);
    await tester.pumpAndSettle(); expect(find.text('new'),findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('daily-report-next'))); await tester.pumpAndSettle();
    expect(find.text('tomorrow'),findsOneWidget);
    expect(reports.opened,['new','old','new','tomorrow']);
    reports.changed=true;
    await tester.tap(find.byTooltip('古い日報へ（左スライド）')); await tester.pumpAndSettle();
    expect(find.text('選んだ日報を取得できませんでした。一覧を再読み込みしてください。'),findsOneWidget);
    expect(find.text('new'),findsNothing);
    expect(tester.takeException(),isNull);
  });
}


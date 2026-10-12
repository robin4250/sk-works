import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/daily_reports/daily_report_calendar_model.dart';
import 'package:sk_works/features/daily_reports/daily_report_month_page.dart';
import 'package:sk_works/features/daily_reports/daily_report_month_repository.dart';
import 'package:sk_works/features/daily_reports/daily_report_repository.dart';
import 'package:sk_works/features/daily_reports/daily_report_saved_preview_pager.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

void main() {
  late SupabaseClient client;
  setUp(() { client = SupabaseClient('https://example.invalid','synthetic-public',
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
    expect(find.descendant(of:noPhotos,matching:find.text('写真無し 1枚')),findsOneWidget);
    expect(find.byKey(const ValueKey('daily-report-day-12-photos')),findsOneWidget);
    await tester.tap(noPhotos); await tester.pumpAndSettle();
    expect(find.text('作業:old'),findsOneWidget);
    await tester.pageBack(); await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('次の月')); await tester.pumpAndSettle();
    expect(find.text('2026年11月'),findsOneWidget);
    expect(reports.requestedMonths.last,11);
    expect(tester.takeException(),isNull);
  });

  testWidgets('same-day photo groups keep each report ID selectable in creation order', (tester) async {
    final reports=Reports(client)..extraOld=true;
    await tester.pumpWidget(MaterialApp(home:DailyReportMonthPage(initialMonth:DateTime(2026,10),
      repositoryForTesting:reports,previewBuilderForTesting:(doc)=>Scaffold(appBar:AppBar(title:Text(doc.report.id)),
        body:Text(doc.report.workDescription)))));
    await tester.pumpAndSettle(); await tester.tap(find.text('現場A')); await tester.pumpAndSettle();
    final button=find.byKey(const ValueKey('daily-report-day-12-no-photos'));
    await tester.scrollUntilVisible(button,400); await tester.pumpAndSettle();
    expect(find.descendant(of:button,matching:find.text('写真無し 2枚')),findsOneWidget);
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

  testWidgets('right swipe opens next saved day, left swipe opens older same-day ID', (tester) async {
    final reports=Reports(client);
    final entries=[entry('new',12,2),entry('old',12,1),entry('tomorrow',13,1)];
    await tester.pumpWidget(MaterialApp(home:DailyReportSavedPreviewPager(repository:reports,actor:'actor',
      entries:entries, initialEntryId:'new',previewBuilderForTesting:(doc)=>Scaffold(body:Center(child:Text(doc.report.id))))));
    await tester.pumpAndSettle();
    await tester.fling(find.byKey(const ValueKey('daily-report-preview-swipe')),const Offset(-350,0),1000);
    await tester.pumpAndSettle(); expect(find.text('old'),findsOneWidget);
    await tester.fling(find.byKey(const ValueKey('daily-report-preview-swipe')),const Offset(350,0),1000);
    await tester.pumpAndSettle(); expect(find.text('tomorrow'),findsOneWidget);
    expect(reports.opened,['new','old','tomorrow']);
    reports.changed=true;
    await tester.tap(find.byTooltip('古い日報へ（左スライド）')); await tester.pumpAndSettle();
    expect(find.text('選んだ日報を取得できませんでした。一覧を再読み込みしてください。'),findsOneWidget);
    expect(find.text('new'),findsNothing);
    expect(tester.takeException(),isNull);
  });
}

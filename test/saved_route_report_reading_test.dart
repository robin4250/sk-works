import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/branding/sko_theme.dart';
import 'package:sk_works/features/attendance/worker_attendance_sheet_page.dart';
import 'package:sk_works/features/attendance/worker_attendance_sheet_repository.dart';
import 'package:sk_works/features/daily_reports/daily_report_month_page.dart';
import 'package:sk_works/features/daily_reports/daily_report_month_repository.dart';
import 'package:sk_works/features/daily_reports/daily_report_pdf_service.dart';
import 'package:sk_works/features/daily_reports/daily_report_repository.dart';
import 'package:sk_works/features/daily_reports/route_visit_report_context.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _date = DateTime(2026, 10, 12);
final _signature = {'strokes': [[{'x': 0.2, 'y': 0.3}, {'x': 0.8, 'y': 0.6}]]};

class _Reports extends DailyReportMonthRepository {
  _Reports(SupabaseClient client) : super(client, DailyReportRepository.forTesting(client));
  bool actorChanged = false;
  String? subject;
  final opened = <String>[];
  @override
  String get actor => 'fixture-actor';
  @override
  void checkActor(String user) {
    if (actorChanged || user != actor) throw StateError('Actor changed');
  }
  @override
  Future<List<DailyReportMonthEntry>> list(DateTime month, {String? workerId}) async {
    subject = workerId;
    return [
      for (var i=0;i<3;i++) DailyReportMonthEntry(
        id: 'visit-$i', date: _date, name: '訪問先${i+1}', status: 'completed', routeId: 'route',
        visitContext: RouteVisitReportContext(sourceClockInId: 'source', routeAssignmentId: 'route',
          routeStopId: 'stop-$i', startCaptureId: 'start-$i', endCaptureId: 'end-$i')),
      DailyReportMonthEntry(id: 'checkout', date: _date, name: '退勤ルート', status: 'signed', routeId: 'route'),
      DailyReportMonthEntry(id: 'yesterday', date: DateTime(2026,10,11), name: '前日の日報', status: 'signed', siteId: 'site'),
    ];
  }
  @override
  Future<DailyReportMonthDocument> loadOne(DailyReportMonthEntry entry, {required String expectedActor}) async {
    checkActor(expectedActor);
    opened.add(entry.id);
    return DailyReportMonthDocument(DailyReportRecord(
      id: entry.id, date: entry.date, siteName: entry.name, routeAssignmentId: entry.routeId,
      status: 'signed', workDescription: '保存済みの作業', workers: [],
      responsibleSignerName: '保存済み責任者', responsibleSignatureJson: _signature,
      reporterSignerName: '保存済み報告者', reporterSignatureJson: _signature,
    ), const []);
  }
}

void main() {
  late SupabaseClient client;
  setUp(() {
    client = SupabaseClient('https://example.invalid', 'synthetic-public',
      authOptions: const AuthClientOptions(autoRefreshToken: false));
  });
  tearDown(() async => client.dispose());
  test('saved object signature and legacy list produce the same visible strokes without changing stored data', () {
    final before = jsonEncode(_signature);
    final svg = DailyReportPdfService.signatureSvg(_signature);
    expect(svg, isNotNull);
    expect(svg, contains('80.0,36.0 320.0,72.0'));
    expect(svg, DailyReportPdfService.signatureSvg(_signature['strokes']));
    expect(jsonEncode(_signature), before);
    expect(DailyReportPdfService.signatureSvg({'strokes': [[{'x': double.nan, 'y': 0.1}]]}), isNull);
  });

  Future<_Reports> pumpList(WidgetTester tester, List<String> previews) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _Reports(client);
    await tester.pumpWidget(MaterialApp(
      theme: SkoTheme.light(SkoTheme.palettes.first),
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(
        textScaler: const TextScaler.linear(1.3)), child: child!),
      home: DailyReportMonthPage(initialDate: _date, workerId: 'selected-worker',
        repositoryForTesting: repository, previewBuilderForTesting: (document) {
          previews.add(document.report.id);
          expect(DailyReportPdfService.signatureSvg(document.report.responsibleSignatureJson), isNotNull);
          return Scaffold(appBar: AppBar(title: Text('preview:${document.report.id}')),
            body: Text(document.report.workDescription));
        }),
    ));
    await tester.pumpAndSettle();
    return repository;
  }

  testWidgets('three visit reports and checkout stay separate and each opens its own saved signature at 320px', (tester) async {
    final previews = <String>[];
    final repository = await pumpList(tester, previews);
    expect(repository.subject, 'selected-worker');
    expect(find.text('前日の日報'), findsNothing);
    for (final label in ['訪問先1', '訪問先2', '訪問先3', '退勤ルート']) {
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(find.text('保存済みの作業'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
    expect(previews, ['visit-0','visit-1','visit-2','checkout']);
    expect(repository.opened, previews);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('changed account cannot open a cached report', (tester) async {
    final previews = <String>[];
    final repository = await pumpList(tester, previews);
    repository.actorChanged = true;
    await tester.tap(find.text('訪問先1'));
    await tester.pumpAndSettle();
    expect(previews, isEmpty);
    expect(find.text('選んだ日報を取得できませんでした。一覧を再読み込みしてください。'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('weekly and calendar show the route title while preserving the original site field', (tester) async {
    const title = '午前A・午後B・夜間Cのルート';
    final day = WorkerAttendanceDay(date: _date, siteName: '元の現場', routeNames: const [title],
      clockIn: DateTime(2026,10,12,8), clockOut: DateTime(2026,10,12,17), manDays: 1);
    final data = WorkerAttendanceMonth(year: 2026, month: 10, days: {_date: day});
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Widget app(Widget child) => MaterialApp(theme: SkoTheme.light(SkoTheme.palettes.first),
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(
        textScaler: const TextScaler.linear(1.3)), child: child!), home: Scaffold(body: child));
    await tester.pumpWidget(app(attendanceWeekForTesting(month: _date,
      week: List.generate(7,(i)=>DateTime(2026,10,12+i)), data: data)));
    expect(find.text(title), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(app(WorkerAttendanceMonthPage(month: _date, data: data, workerName: '社員')));
    await tester.pumpAndSettle();
    expect(find.text(title), findsOneWidget);
    expect(tester.widget<Text>(find.text(title)).overflow, TextOverflow.clip);
    expect(day.siteName, '元の現場');
    expect(day.manDays, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

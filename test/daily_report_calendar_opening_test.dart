// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/daily_reports/daily_report_month_page.dart';
import 'package:sk_works/features/daily_reports/daily_report_month_repository.dart';
import 'package:sk_works/features/daily_reports/daily_report_repository.dart';
import 'package:sk_works/features/daily_reports/daily_report_saved_preview_pager.dart';

class _Reports extends DailyReportMonthRepository {
  _Reports(SupabaseClient client) : super(client, DailyReportRepository.forTesting(client));
  bool deny = false;
  int loads = 0;
  final record = DailyReportMonthEntry(id: 'saved-one', date: DateTime(2026, 10, 1),
    name: 'Calendar site', status: 'signed', siteId: 'site-one');
  @override
  String get actor => 'synthetic-actor';
  @override
  void checkActor(String actor) {
    if (deny || actor != this.actor) throw StateError('Synthetic refusal');
  }
  @override
  Future<List<DailyReportMonthEntry>> list(DateTime month, {String? workerId}) async => [record];
  @override
  Future<DailyReportSiteHistoryResult> listSiteHistory(DailyReportMonthEntry anchor, {String? workerId}) async =>
    DailyReportSiteHistoryResult([record]);
  @override
  Future<bool> hasPhotos(DailyReportMonthEntry entry, {required String expectedActor}) async => false;
  @override
  Future<DailyReportMonthDocument> loadOne(DailyReportMonthEntry entry, {required String expectedActor}) async {
    checkActor(expectedActor);
    loads++;
    return DailyReportMonthDocument(DailyReportRecord(id: entry.id, date: entry.date,
      siteId: entry.siteId, siteName: entry.name, workDescription: 'Saved content',
      status: 'signed', workers: const []), const []);
  }
}

class _Observer extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
    super.didPush(route, previousRoute);
  }
}

Future<VoidCallback> _openCalendar(WidgetTester tester, _Reports repository, _Observer observer) async {
  await tester.pumpWidget(MaterialApp(navigatorObservers: [observer],
    home: DailyReportMonthPage(initialMonth: DateTime(2026, 10),
      repositoryForTesting: repository,
      previewBuilderForTesting: (document) => Scaffold(appBar: AppBar(title: const Text('Saved preview')),
        body: Text(document.report.workDescription)))));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Calendar site'));
  await tester.pumpAndSettle();
  return tester.widget<OutlinedButton>(
    find.byKey(const ValueKey('daily-report-day-1-no-photos'))).onPressed!;
}

void main() {
  late SupabaseClient client;
  setUp(() {
    client = SupabaseClient('https://example.invalid', 'synthetic-public',
      authOptions: const AuthClientOptions(autoRefreshToken: false));
  });
  tearDown(() async => client.dispose());

  testWidgets('retained calendar callback opens one preview and releases after returning', (tester) async {
    final repository = _Reports(client);
    final observer = _Observer();
    final open = await _openCalendar(tester, repository, observer);
    final before = observer.pushes;
    open();
    open();
    expect(observer.pushes - before, 1);
    await tester.pumpAndSettle();
    expect(find.byType(DailyReportSavedPreviewPager, skipOffstage: false), findsOneWidget);
    expect(repository.loads, 1);
    await tester.pageBack();
    await tester.pumpAndSettle();
    final reopen = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('daily-report-day-1-no-photos'))).onPressed!;
    reopen();
    await tester.pumpAndSettle();
    expect(observer.pushes - before, 2);
    expect(repository.loads, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed pre-navigation check releases calendar opening for explicit retry', (tester) async {
    final repository = _Reports(client);
    final observer = _Observer();
    final open = await _openCalendar(tester, repository, observer);
    final before = observer.pushes;
    repository.deny = true;
    open();
    await tester.pumpAndSettle();
    expect(observer.pushes, before);
    expect(find.text('選んだ日報を取得できませんでした。一覧を再読み込みしてください。'), findsOneWidget);
    repository.deny = false;
    open();
    await tester.pumpAndSettle();
    expect(observer.pushes - before, 1);
    expect(repository.loads, 1);
    expect(tester.takeException(), isNull);
  });
}


import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/daily_reports/daily_report_month_page.dart';
import 'package:sk_works/features/daily_reports/daily_report_month_repository.dart';
import 'package:sk_works/features/daily_reports/daily_report_repository.dart';

class _Reports extends DailyReportMonthRepository {
  _Reports(SupabaseClient client) : super(client, DailyReportRepository.forTesting(client));
  int pendingReads = 0;
  @override String get actor => 'synthetic-actor';
  @override void checkActor(String value) {
    if (value != actor) throw StateError('Synthetic actor changed');
  }
  @override Future<List<DailyReportMonthEntry>> list(DateTime month, {String? workerId}) async => [
    DailyReportMonthEntry(id: 'saved', date: DateTime(2026, 10, 1), name: '保存現場',
      siteId: 'saved-site', status: 'signed'),
    DailyReportMonthEntry(id: 'input', date: DateTime(2026, 10, 2), name: '入力現場',
      siteId: 'input-site', status: 'draft'),
    DailyReportMonthEntry(id: 'finalization', date: DateTime(2026, 10, 3), name: '入力現場',
      siteId: 'input-site', status: 'draft', reporterSigned: true, supervisorSigned: true),
  ];
  @override Future<DailyReportPendingResult> listPending({String? workerId}) async {
    pendingReads++;
    return DailyReportPendingResult([
      DailyReportMonthEntry(id: 'older-pending', date: DateTime(2025, 1, 2), name: 'サイン現場',
        siteId: 'pending-site', status: 'draft', reporterSigned: true),
    ]);
  }
}

class _Routes extends NavigatorObserver {
  int pushes = 0;
  @override void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
    super.didPush(route, previousRoute);
  }
}

void main() {
  late SupabaseClient client;
  late _Reports reports;
  late _Routes routes;
  setUp(() {
    // Create SDK resources outside the widget FakeAsync zone, matching the
    // existing calendar fixtures. Their asynchronous disposal needs real time.
    client = SupabaseClient('https://example.invalid', 'synthetic-public',
      authOptions: const AuthClientOptions(autoRefreshToken: false));
    reports = _Reports(client);
    routes = _Routes();
  });
  tearDown(() async {
    await client.dispose().timeout(const Duration(seconds: 5));
  });
  testWidgets('phone filters retain one header and site-card hierarchy without hiding older pending reports', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? opened;
    await tester.pumpWidget(MaterialApp(navigatorObservers: [routes],
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(
        textScaler: const TextScaler.linear(1.3)), child: child!),
      home: DailyReportMonthPage(initialMonth: DateTime(2026, 10), repositoryForTesting: reports,
        pendingBuilderForTesting: (entry) {
          opened = entry.id;
          return Scaffold(appBar: AppBar(), body: Text('既存日報 ${entry.id}'));
        })));
    await tester.pumpAndSettle();
    final initialPushes = routes.pushes;
    final filterTop = tester.getTopLeft(find.byKey(const ValueKey('daily-report-saved-filter'))).dy;
    final share = find.byKey(const ValueKey('daily-report-month-share'));
    expect(find.text('日報'), findsOneWidget);
    expect(find.text('保存済み 1件'), findsOneWidget);
    expect(tester.widget<FilledButton>(share).onPressed, isNotNull);
    final savedTile = tester.widget<ListTile>(find.byKey(const ValueKey('daily-report-site-site:saved-site')));
    final savedStyle = (savedTile.title! as Text).style;

    await tester.tap(find.byKey(const ValueKey('daily-report-pending-filter')));
    await tester.pumpAndSettle();
    expect(routes.pushes, initialPushes);
    expect(find.text('日報'), findsOneWidget);
    expect(find.text('すべての月'), findsOneWidget);
    expect(find.text('すべての月・現場別'), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(const ValueKey('daily-report-saved-filter'))).dy,
      closeTo(filterTop, 0.1));
    expect(tester.widget<FilledButton>(share).onPressed, isNull,
      reason: 'All-month pending must never export the current saved-month collection');
    final pendingSite = find.byKey(const ValueKey('daily-report-pending-site-site:pending-site'));
    final pendingTile = tester.widget<ListTile>(pendingSite);
    expect((pendingTile.title! as Text).style, savedStyle);
    await tester.tap(pendingSite);
    await tester.pumpAndSettle();
    expect(routes.pushes, initialPushes);
    expect(find.text('2025-01-02'), findsOneWidget,
      reason: 'Pending scope stays all months, not the selected October');
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('daily-report-pending-entry-older-pending')),
      matching: find.text('サイン')));
    await tester.pumpAndSettle();
    expect(opened, 'older-pending');
    expect(routes.pushes, initialPushes + 1);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(reports.pendingReads, 2);

    await tester.tap(find.byKey(const ValueKey('daily-report-unfinished-filter')));
    await tester.pumpAndSettle();
    expect(find.text('日報'), findsOneWidget);
    expect(find.text('2026年10月'), findsOneWidget);
    expect(find.text('入力途中 1件'), findsOneWidget);
    expect(find.text('確定待ち 1件'), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(const ValueKey('daily-report-saved-filter'))).dy,
      closeTo(filterTop, 0.1));
    final inputTile = tester.widget<ListTile>(find.byKey(const ValueKey('daily-report-site-site:input-site')));
    expect((inputTile.title! as Text).style, savedStyle);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    debugPrint('Daily list style: all phone layout, scope and navigation assertions completed.');
  }, timeout: const Timeout(Duration(minutes: 2)));
}

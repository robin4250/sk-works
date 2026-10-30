// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/daily_reports/daily_report_page.dart';
import 'package:sk_works/features/daily_reports/daily_report_repository.dart';
import 'package:sk_works/features/daily_reports/daily_report_company_allowance_selection.dart';
import 'package:sk_works/features/shared/company_allowance_label_repository.dart';
import 'daily_report_approved_edit_start_test.dart' show EditableReports;

class BlockedEditReports extends EditableReports {
  BlockedEditReports(super.client);
  bool blocked = true;
  Future<void>? pendingSave;
  String reportIdValue = 'report-a', companyIdValue = 'company-a', siteIdValue = 'site-a';
  @override Future<bool> hasApprovedEdit(String reportId) async => approved;
  final member = DailyReportWorkerDraft(workerId: 'worker-a', workerName: '合成メンバー',
    workCategory: 'day', overtimeHours: 3, allowanceLabel: 'PC',
    companyAllowanceSelections: DailyReportCompanyAllowanceSelections.fromJson({
      'contract_version': 1, 'items': [{'origin': 'company_common',
        'id': '10000000-0000-4000-8000-000000000001', 'generation': null,
        'registration_version': 0, 'name_snapshot': 'PC', 'unit': 'day'}]}));
  @override Future<DailyReportRecord?> loadReport({required DateTime date,
    String? siteId, String? routeAssignmentId, String? vehicleClockInAnchorId,
    String? reportId}) async => DailyReportRecord(id: reportIdValue, companyId: companyIdValue,
      date: date, siteId: siteIdValue, siteName: '対象現場', workDescription: '保存済み内容',
      status: signed ? 'signed' : 'draft', workers: [member],
      reporterSignatureJson: signed ? {'strokes': [[{'x': 0.1, 'y': 0.2}, {'x': 0.3, 'y': 0.4}]]} : null,
      responsibleSignatureJson: signed ? {'strokes': [[{'x': 0.1, 'y': 0.2}, {'x': 0.3, 'y': 0.4}]]} : null);
  @override Future<bool> vehicleMeterEnabledForAnchor(String? anchor) async => false;
  @override Future<CompanyAllowanceLabelSnapshot> loadCompanyAllowanceLabels({
    required Iterable<String> workerIds, String? expectedCompanyId}) async =>
      const CompanyAllowanceLabelSnapshot(companyId: 'company-a', version: 1, items: []);
  @override Future<Map<String, Set<String>>> loadCompanyAllowanceEligibility({
    required String reportId, required Iterable<String> workerIds,
    required CompanyAllowanceLabelSnapshot snapshot}) async => {'worker-a': {}};
  @override Future<String> saveDraft({String? reportId, String? siteId,
    String? routeAssignmentId, required DateTime date, required String workDescription,
    required List<DailyReportWorkerDraft> workers, String? groupClockInAnchorId,
    String? vehicleClockInAnchorId}) async {
    if (blocked) {
      saves++;
      if (pendingSave != null) await pendingSave;
      throw StateError('退勤手当の給与連動を確認できません。再読み込みしてください');
    }
    return super.saveDraft(reportId: reportId, siteId: siteId, routeAssignmentId: routeAssignmentId,
      date: date, workDescription: workDescription, workers: workers,
      groupClockInAnchorId: groupClockInAnchorId, vehicleClockInAnchorId: vehicleClockInAnchorId);
  }
}

void main() {
  late SupabaseClient client;
  setUp(() {
    final previous = SharedPreferencesAsyncPlatform.instance;
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    addTearDown(() => SharedPreferencesAsyncPlatform.instance = previous);
    client = SupabaseClient('https://example.invalid', 'synthetic-public',
      authOptions: const AuthClientOptions(autoRefreshToken: false));
  });
  tearDown(() async { await client.dispose(); });
  testWidgets('failed approved start explains grey controls and successful retry permits saved PC removal', (tester) async {
    final repo = BlockedEditReports(client);
    await tester.pumpWidget(MaterialApp(home: DailyReportPage(initialDate: DateTime(2026, 10, 15),
      initialSiteId: 'site-a', initialReportId: 'report-a', repositoryForTesting: repo)));
    await tester.pumpAndSettle();
    Future<void> reveal(Finder finder) async {
      final scrollable = find.byWidgetPredicate((widget) => widget is Scrollable && widget.axisDirection == AxisDirection.down).first;
      tester.state<ScrollableState>(scrollable).position.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(finder, 250, scrollable: scrollable, maxScrolls: 40);
      await tester.ensureVisible(finder); await tester.pumpAndSettle();
    }
    Future<void> start() async {
      final start = find.byKey(const ValueKey('daily-report-begin-approved-edit'));
      await reveal(start); await tester.tap(start); await tester.pumpAndSettle();
      await tester.tap(find.text('編集を開始').last); await tester.pumpAndSettle();
    }
    await start();
    final failure = find.byKey(const ValueKey('daily-report-approved-edit-start-failure'));
    expect(failure, findsOneWidget);
    expect(find.descendant(of: failure, matching: find.text('退勤手当の給与連動を確認できません。再読み込みしてください')), findsOneWidget);
    expect(repo.signed, isTrue);
    expect(repo.approved, isTrue);
    expect(repo.member.allowanceLabel, 'PC');
    repo.blocked = false;
    await start();
    expect(repo.signed, isFalse);
    expect(repo.approved, isFalse);
    expect(failure, findsNothing);
    final details = find.byKey(const ValueKey('worker-details/worker-a/false'));
    await reveal(details);
    final member = find.descendant(of: details, matching: find.text('合成メンバー')).first;
    await tester.tap(member); await tester.pumpAndSettle();
    final chip = find.widgetWithText(InputChip, 'PC（保存済み）');
    await reveal(chip);
    expect(tester.widget<InputChip>(chip).onDeleted, isNotNull);
    tester.widget<InputChip>(chip).onDeleted!(); await tester.pumpAndSettle();
    expect(repo.member.companyAllowanceSelections!.items, isEmpty);
    expect(chip, findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('queued failure from the previous report never appears on a replacement company report', (tester) async {
    final pending = Completer<void>();
    final old = BlockedEditReports(client)..pendingSave = pending.future;
    await tester.pumpWidget(MaterialApp(home: DailyReportPage(key: const ValueKey('old-report'),
      initialDate: DateTime(2026, 10, 15), initialSiteId: 'site-a',
      initialReportId: 'report-a', repositoryForTesting: old)));
    await tester.pumpAndSettle();
    final start = find.byKey(const ValueKey('daily-report-begin-approved-edit'));
    final scrollable = find.byWidgetPredicate((widget) => widget is Scrollable && widget.axisDirection == AxisDirection.down).first;
    await tester.scrollUntilVisible(start, 250, scrollable: scrollable, maxScrolls: 40);
    await tester.ensureVisible(start); await tester.tap(start); await tester.pumpAndSettle();
    await tester.tap(find.text('編集を開始').last); await tester.pumpAndSettle();
    expect(old.saves, 1);
    final next = BlockedEditReports(client)..reportIdValue = 'report-b'
      ..companyIdValue = 'company-b'..siteIdValue = 'site-b';
    await tester.pumpWidget(MaterialApp(home: DailyReportPage(key: const ValueKey('new-report'),
      initialDate: DateTime(2026, 10, 16), initialSiteId: 'site-b',
      initialReportId: 'report-b', repositoryForTesting: next)));
    await tester.pumpAndSettle();
    pending.complete(); await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('daily-report-approved-edit-start-failure')), findsNothing);
    expect(find.text('退勤手当の給与連動を確認できません。再読み込みしてください'), findsNothing);
    expect(next.signed, isTrue);
    expect(next.saves, 0);
    expect(tester.takeException(), isNull);
  });
}

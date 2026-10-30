// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:sk_works/features/daily_reports/daily_report_page.dart';
import 'package:sk_works/features/daily_reports/daily_report_edit_session.dart';
import 'package:sk_works/features/daily_reports/shared_daily_report_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'daily_report_approved_edit_start_test.dart' show EditableReports;

class _ResumeShared implements SharedDailyReportRepository {
  _ResumeShared(this.reports);
  final EditableReports reports;
  int resumeCalls = 0;
  bool deny = false, commitThenThrow = false;
  String request = 'request-a';
  SharedDailyReportContext get state => SharedDailyReportContext(
    actorId: reports.currentActorId!, companyId: 'company-a', reportId: 'report-a',
    workDate: DateTime(2026, 10, 15), reportStatus: 'draft',
    state: reports.responsible != null ? 'supervisor_saved' : 'reporter_required',
    enabled: true, canManageAttendance: false, reporterSaved: reports.reporterSigned,
    supervisorSaved: reports.responsible != null, sourceAttached: false,
    expectedUpdatedAt: DateTime.utc(2026, 10, 15, 8),
    signatureScopeFingerprint: List.filled(64, 'a').join(),
    firstReporterCoversWorkOnly: true, approvedEditRequestId: request,
    supervisorReady: true, hoursAnnex: {'enabled': true, 'required': false,
      'ready': true, 'inputs': <Map<String, dynamic>>[]},
    workBasis: {'report': {'work_description': '保存済み内容', 'site_id': 'site-a',
      'route_assignment_id': null}, 'roster': <Map<String, dynamic>>[]});
  @override Future<SharedDailyReportContext> loadReport(String reportId,
    {String? expectedActor}) async => state;
  @override Future<SharedDailyReportContext> resumeApprovedSignatures({
    required SharedDailyReportContext before, required String requestId}) async {
    resumeCalls++;
    expect(requestId, 'request-a'); expect(before.approvedEditRequestId, requestId);
    if (deny) throw StateError('編集を再開できません');
    reports.reporterSigned = false; reports.reporter = null; reports.responsible = null;
    if (commitThenThrow) { commitThenThrow = false; throw StateError('応答消失'); }
    return state;
  }
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
  tearDown(() async => client.dispose());
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    final scrollable = find.byWidgetPredicate((widget) => widget is Scrollable &&
      widget.axisDirection == AxisDirection.down).first;
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(finder, 250, scrollable: scrollable, maxScrolls: 40);
    await tester.ensureVisible(finder); await tester.pumpAndSettle();
  }
  for (final approved in [false, true]) {
    testWidgets('saved signature preview exposes only an approved explicit edit entrance approved=$approved', (tester) async {
      final reports = EditableReports(client)..approved = approved
        ..responsible = {'strokes': [[{'x': 0.1, 'y': 0.1}]]};
      await tester.pumpWidget(MaterialApp(home: DailyReportPage(initialDate: DateTime(2026, 10, 15),
        initialSiteId: 'site-a', initialReportId: 'report-a', repositoryForTesting: reports)));
      await tester.pumpAndSettle();
      final responsible = find.ancestor(of: find.text('責任者サイン'), matching: find.byType(ListTile));
      await reveal(tester, responsible); await tester.tap(responsible); await tester.pumpAndSettle();
      expect(reports.saves, 0); expect(reports.signed, isTrue);
      final edit = find.byKey(const ValueKey('daily-report-signature-preview-begin-edit'));
      expect(edit, approved ? findsOneWidget : findsNothing);
      if (approved) {
        await tester.tap(edit); await tester.pumpAndSettle();
        expect(find.text('編集を開始').last, findsOneWidget);
        expect(reports.saves, 0); expect(reports.signed, isTrue);
        await tester.tap(find.text('キャンセル').last); await tester.pumpAndSettle();
        expect(reports.saves, 0); expect(reports.signed, isTrue);
      } else {
        await tester.tap(find.text('閉じる').last); await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    });
  }
  for (final mode in ['success', 'denied', 'lost-reply']) {
    final denied = mode == 'denied';
    testWidgets('stranded approval resumes explicitly without a second application mode=$mode', (tester) async {
      final reports = EditableReports(client)..signed = false..approved = false..reporterSigned = true
        ..responsible = {'strokes': [[{'x': 0.1, 'y': 0.1}]]};
      final shared = _ResumeShared(reports)..deny = denied..commitThenThrow = mode == 'lost-reply';
      await DailyReportEditSessionStore().remember(const DailyReportEditSession(
        actorId: 'owner', companyId: 'company-a', reportId: 'report-a', requestId: 'request-a'));
      await tester.pumpWidget(MaterialApp(home: DailyReportPage(initialDate: DateTime(2026, 10, 15),
        initialSiteId: 'site-a', initialReportId: 'report-a', repositoryForTesting: reports,
        sharedReportRepositoryForTesting: shared)));
      await tester.pumpAndSettle();
      expect(shared.resumeCalls, 0); expect(reports.saves, 0);
      // The old signature remains a preview; an unconfirmed used request does
      // not by itself authorize new signature capture.
      expect(find.byKey(const ValueKey('daily-report-finish-approved-edit')), findsNothing);
      final start = find.byKey(const ValueKey('daily-report-resume-approved-signatures'));
      await reveal(tester, start); await tester.tap(start); await tester.pumpAndSettle();
      expect(shared.resumeCalls, 0);
      await tester.tap(find.text('戻る').last); await tester.pumpAndSettle();
      expect(shared.resumeCalls, 0); expect(reports.responsible, isNotNull);
      await reveal(tester, start); await tester.tap(start); await tester.pumpAndSettle();
      await tester.tap(find.text('編集を再開').last); await tester.pumpAndSettle();
      expect(shared.resumeCalls, 1); expect(reports.saves, 0); expect(reports.approved, isFalse);
      if (mode == 'lost-reply') {
        expect(reports.responsible, isNull);
        expect((await DailyReportEditSessionStore().load('owner', 'report-a'))?.confirmed, isFalse);
        // An observed unsigned draft is not silently a success. The same exact
        // approved-session action remains available for an authoritative retry.
        await reveal(tester, start);
        expect(start, findsOneWidget); await tester.tap(start); await tester.pumpAndSettle();
        await tester.tap(find.text('編集を再開').last); await tester.pumpAndSettle();
        expect(shared.resumeCalls, 2); expect(reports.saves, 0);
      }
      final session = await DailyReportEditSessionStore().load('owner', 'report-a');
      expect(session?.confirmed, !denied);
      if (denied) {
        expect(reports.responsible, isNotNull); expect(start, findsOneWidget);
      } else {
        expect(reports.responsible, isNull); expect(start, findsNothing);
        final reporter = find.ancestor(of: find.text('報告者サイン'), matching: find.byType(ListTile));
        await reveal(tester, reporter); expect(tester.widget<ListTile>(reporter).onTap, isNotNull);
        final responsible = find.ancestor(of: find.text('責任者サイン'), matching: find.byType(ListTile));
        await reveal(tester, responsible); expect(tester.widget<ListTile>(responsible).onTap, isNotNull);
      }
      expect(tester.takeException(), isNull);
    });
  }
}

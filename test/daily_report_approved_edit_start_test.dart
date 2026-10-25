// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:sk_works/features/daily_reports/daily_report_page.dart';
import 'package:sk_works/features/daily_reports/daily_report_edit_session.dart';
import 'package:sk_works/features/daily_reports/signature_capture_page.dart';
import 'package:sk_works/features/daily_reports/daily_report_repository.dart';
import 'package:sk_works/features/daily_reports/shared_daily_report_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EditableReports extends DailyReportRepository {
  EditableReports(super.client) : super.forTesting();
  bool approved = true, signed = true, failSave = false;
  String actor = 'owner';
  int saves = 0, signCalls = 0, reporterCalls = 0;
  Object? reporter;
  bool reporterSigned = false, failSign = false, commitThenThrow = false;
  Object? responsible;
  String? responsibleName;
  @override
  Future<DailyReportEditSession?> approvedEditSession(DailyReportRecord report) async =>
    approved ? const DailyReportEditSession(actorId: 'owner', companyId: 'company-a',
      reportId: 'report-a', requestId: 'request-a') : null;
  @override
  Future<bool> verifyEditSession(DailyReportEditSession session) async =>
    !approved && session.requestId == 'request-a' && session.actorId == 'owner' &&
    session.companyId == 'company-a' && session.reportId == 'report-a';
  @override
  Future<String> loadResponsibleName({String? siteId, String? routeAssignmentId}) async => '責任者';
  @override
  Future<void> saveReporterSignature({required String reportId,
    required String signerName, required Object signatureJson}) async {
    reporterCalls++;
    expect(reportId, 'report-a');
    expect(signerName, '報告者');
    reporterSigned = true;
    reporter = {'strokes': signatureJson};
  }
  @override
  Future<void> sign({required String reportId, required String signerName,
    required Object signatureJson}) async {
    signCalls++;
    if (failSign) throw StateError('offline');
    signed = true;
    responsible = {'strokes': signatureJson};
    responsibleName = signerName;
    if (commitThenThrow) throw StateError('response lost');
  }
  @override
  String? get currentActorId => actor;
  @override
  String? get notificationRetryUserId => null;
  @override
  Future<bool> hasApprovedEdit(String reportId) async {
    expect(reportId, 'report-a');
    return approved;
  }
  @override
  Future<DailyReportRecord?> loadReport({required DateTime date,
    String? siteId, String? routeAssignmentId, String? vehicleClockInAnchorId,
    String? reportId}) async => DailyReportRecord(
      id: 'report-a', companyId: 'company-a', date: date, siteId: 'site-a', siteName: '対象現場',
      workDescription: '保存済み内容', status: signed ? 'signed' : 'draft', workers: [],
      reporterSignatureJson: reporter ?? (signed || reporterSigned
        ? {'strokes': [[{'x': 0.1, 'y': 0.2}]]} : null),
      responsibleSignerName: responsibleName,
      responsibleSignatureJson: responsible ?? (signed ? {'strokes': []} : null));
  @override
  Future<List<DailyReportEvidenceRecord>> loadAttendanceEvidence({String? reportId,
    required DateTime date, String? siteId, String? routeAssignmentId}) async => [];
  @override
  Future<String> saveDraft({String? reportId, String? siteId,
    String? routeAssignmentId, required DateTime date, required String workDescription,
    required List<DailyReportWorkerDraft> workers, String? groupClockInAnchorId,
    String? vehicleClockInAnchorId}) async {
    saves++;
    expect(reportId, 'report-a');
    expect(workDescription, '保存済み内容');
    if (failSave || !approved) throw StateError('save denied');
    signed = false;
    reporterSigned = false;
    approved = false;
    return reportId!;
  }
}

class ApprovedSharedReports implements SharedDailyReportRepository {
  ApprovedSharedReports(this.reports);
  final EditableReports reports;
  String scope = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  String requestId = 'request-a';
  bool commitThenThrow = false;
  int approvedWrites = 0;
  final submittedScopes = <String?>[];
  SharedDailyReportContext get state => SharedDailyReportContext(
    actorId: 'owner', companyId: 'company-a', reportId: 'report-a',
    workDate: DateTime(2026, 10, 15),
    state: reports.signed ? 'supervisor_saved' : 'reporter_saved_waiting_supervisor',
    enabled: true, canManageAttendance: false, reporterSaved: true,
    supervisorSaved: reports.signed, sourceAttached: false,
    expectedUpdatedAt: DateTime.utc(2026, 10, 15, 8), signatureScopeFingerprint: scope,
    firstReporterCoversWorkOnly: true, approvedEditRequestId: requestId,
    supervisorReady: true, hoursAnnex: {'enabled': true, 'required': false,
      'ready': true, 'inputs': <Map<String, dynamic>>[]},
    workBasis: {'report': {'work_description': '保存済み内容',
      'site_id': 'site-a', 'route_assignment_id': null},
      'roster': <Map<String, dynamic>>[]});
  @override Future<SharedDailyReportContext> loadReport(String reportId, {String? expectedActor}) async => state;
  @override Future<SharedDailyReportContext> collectApprovedSupervisor({
    required SharedDailyReportContext before, required String requestId,
    required String signerName, required Map<String, dynamic> signature}) async {
    approvedWrites++;
    submittedScopes.add(before.signatureScopeFingerprint);
    expect(requestId, 'request-a');
    expect(before.approvedEditRequestId, requestId);
    expect(before.canManageAttendance, isFalse);
    if (before.signatureScopeFingerprint != scope) throw StateError('signature scope changed');
    reports.signed = true;
    reports.responsible = signature;
    reports.responsibleName = signerName;
    if (commitThenThrow) throw StateError('response lost');
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
  tearDown(() async { await client.dispose(); });

  Future<void> open(WidgetTester tester, EditableReports repo, {ApprovedSharedReports? shared}) async {
    await tester.pumpWidget(MaterialApp(home: DailyReportPage(
      initialDate: DateTime(2026, 10, 15), initialSiteId: 'site-a',
      initialReportId: 'report-a', repositoryForTesting: repo,
      sharedReportRepositoryForTesting: shared)));
    await tester.pumpAndSettle();
  }
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    final scrollable = find.byWidgetPredicate((widget) =>
      widget is Scrollable && widget.axisDirection == AxisDirection.down).first;
    if (finder.evaluate().isEmpty) {
      tester.state<ScrollableState>(scrollable).position.jumpTo(0);
      await tester.pumpAndSettle();
    }
    await tester.scrollUntilVisible(finder, 250, scrollable: scrollable, maxScrolls: 30);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  Future<void> begin(WidgetTester tester) async {
    final button = find.byKey(const ValueKey('daily-report-begin-approved-edit'));
    await reveal(tester, button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('opening approval never clears signatures; explicit start enables both signatures',
    (tester) async {
      final repo = EditableReports(client);
      await open(tester, repo);
      expect(repo.saves, 0);
      expect(repo.signed, isTrue);
      await begin(tester);
      expect(repo.saves, 0);
      await tester.tap(find.text('編集を開始').last);
      await tester.pumpAndSettle();
      expect(repo.saves, 1);
      expect(repo.signed, isFalse);
      expect(find.byKey(const ValueKey('daily-report-begin-approved-edit')), findsNothing);
      final reporterTile = find.ancestor(of: find.text('報告者サイン'), matching: find.byType(ListTile));
      await reveal(tester, reporterTile);
      final reporter = tester.widget<ListTile>(reporterTile);
      expect(reporter.onTap, isNotNull);
      final supervisorTile = find.ancestor(of: find.text('責任者サイン'), matching: find.byType(ListTile));
      await reveal(tester, supervisorTile);
      final supervisor = tester.widget<ListTile>(supervisorTile);
      expect(supervisor.onTap, isNotNull);
    });
  testWidgets('signed shared v2 explicitly consumes approval before enabling correction', (tester) async {
    final repo = EditableReports(client);
    final shared = ApprovedSharedReports(repo);
    await open(tester, repo, shared: shared);
    expect(repo.saves, 0);
    expect(repo.signed, isTrue);
    await begin(tester);
    expect(repo.saves, 0);
    await tester.tap(find.text('編集を開始').last);
    await tester.pumpAndSettle();
    expect(repo.saves, 1);
    expect(repo.signed, isFalse);
    expect(repo.approved, isFalse);
    expect(shared.approvedWrites, 0);
    expect(find.byKey(const ValueKey('daily-report-begin-approved-edit')), findsNothing);
    // The registration snackbar may still precede the success snackbar. Verify
    // the durable confirmed session and unlocked correction controls instead.
    final session = await DailyReportEditSessionStore().load('owner', 'report-a');
    expect(session?.confirmed, isTrue);
    expect(session?.requestId, 'request-a');
    final reporterTile = find.ancestor(of: find.text('報告者サイン'), matching: find.byType(ListTile));
    await reveal(tester, reporterTile);
    expect(tester.widget<ListTile>(reporterTile).onTap, isNotNull);
  });
  testWidgets('revoked shared v2 approval cannot bypass frozen report', (tester) async {
    final repo = EditableReports(client);
    final shared = ApprovedSharedReports(repo);
    await open(tester, repo, shared: shared);
    repo.approved = false;
    await begin(tester);
    await tester.tap(find.text('編集を開始').last);
    await tester.pumpAndSettle();
    expect(repo.saves, 0);
    expect(repo.signed, isTrue);
    expect(shared.approvedWrites, 0);
  });
  testWidgets('no approved request keeps signed report locked', (tester) async {
    final repo = EditableReports(client)..approved = false;
    await open(tester, repo);
    expect(find.byKey(const ValueKey('daily-report-begin-approved-edit')), findsNothing);
    expect(repo.saves, 0);
    final reporterTile = find.ancestor(of: find.text('報告者サイン'), matching: find.byType(ListTile));
    await reveal(tester, reporterTile);
    final reporter = tester.widget<ListTile>(reporterTile);
    expect(reporter.onTap, isNull);
  });
  testWidgets('cancel or save failure never reports successful edit start', (tester) async {
    final repo = EditableReports(client)..failSave = true;
    await open(tester, repo);
    await begin(tester);
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(repo.saves, 0);
    await begin(tester);
    await tester.tap(find.text('編集を開始').last);
    await tester.pumpAndSettle();
    expect(repo.saves, 1);
    expect(repo.signed, isTrue);
    expect(find.text('編集できる状態になりました。編集後は報告者・責任者のサインを登録してください。'), findsNothing);
  });
  testWidgets('approval revoked after load cannot start editing', (tester) async {
    final repo = EditableReports(client);
    await open(tester, repo);
    repo.approved = false;
    await begin(tester);
    await tester.tap(find.text('編集を開始').last);
    await tester.pumpAndSettle();
    expect(repo.saves, 0);
    expect(repo.signed, isTrue);
  });
  Future<void> prepareCompletion(WidgetTester tester, EditableReports repo) async {
    repo.signed = false;
    repo.approved = false;
    repo.reporterSigned = true;
    await DailyReportEditSessionStore().remember(const DailyReportEditSession(
      actorId: 'owner', companyId: 'company-a', reportId: 'report-a',
      requestId: 'request-a', confirmed: true));
    await open(tester, repo);
    final tile = find.ancestor(of: find.text('責任者サイン'), matching: find.byType(ListTile));
    await reveal(tester, tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.byType(SignatureCapturePage), findsOneWidget);
    Navigator.of(tester.element(find.byType(SignatureCapturePage))).pop(
      const SignatureResult(signerName: '責任者',
        strokes: [[Offset(0.3, 0.4), Offset(0.5, 0.6)]]));
    await tester.pumpAndSettle();
  }

  Future<void> prepareV2Completion(WidgetTester tester, EditableReports repo,
      ApprovedSharedReports shared, {VoidCallback? whileDrawing}) async {
    repo.signed = false;
    repo.approved = false;
    repo.reporterSigned = true;
    await DailyReportEditSessionStore().remember(const DailyReportEditSession(
      actorId: 'owner', companyId: 'company-a', reportId: 'report-a',
      requestId: 'request-a', confirmed: true));
    await open(tester, repo, shared: shared);
    final tile = find.ancestor(of: find.text('責任者サイン'), matching: find.byType(ListTile));
    await reveal(tester, tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.text('責任者サインで確認する内容'), findsOneWidget);
    await tester.tap(find.text('この内容で責任者サインへ'));
    await tester.pumpAndSettle();
    expect(find.byType(SignatureCapturePage), findsOneWidget);
    whileDrawing?.call();
    Navigator.of(tester.element(find.byType(SignatureCapturePage))).pop(
      const SignatureResult(signerName: '責任者',
        strokes: [[Offset(0.3, 0.4), Offset(0.5, 0.6)]]));
    await tester.pumpAndSettle();
  }

  testWidgets('approved v2 completion uses exact session wrapper without granting manager or ordinary signing', (tester) async {
    final repo = EditableReports(client);
    final shared = ApprovedSharedReports(repo);
    await prepareV2Completion(tester, repo, shared);
    final finish = find.byKey(const ValueKey('daily-report-finish-approved-edit'));
    await reveal(tester, finish);
    await tester.tap(finish);
    await tester.pumpAndSettle();
    expect(shared.approvedWrites, 1);
    expect(repo.signCalls, 0);
    expect(find.text('日報の編集を完了しました。保存して確定しました。'), findsOneWidget);
  });

  testWidgets('approved v2 drawing keeps its original evidence scope on explicit retries', (tester) async {
    final repo = EditableReports(client);
    final shared = ApprovedSharedReports(repo);
    final reviewedScope = shared.scope;
    await prepareV2Completion(tester, repo, shared, whileDrawing: () {
      shared.scope = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    });
    final finish = find.byKey(const ValueKey('daily-report-finish-approved-edit'));
    await reveal(tester, finish);
    for (var attempt = 0; attempt < 2; attempt++) {
      await tester.tap(finish);
      await tester.pumpAndSettle();
    }
    expect(shared.submittedScopes, [reviewedScope, reviewedScope]);
    expect(repo.signCalls, 0);
    expect(repo.signed, isFalse);
    expect(find.text('日報の編集を完了しました。保存して確定しました。'), findsNothing);
  });

  testWidgets('approved v2 lost response reloads the exact final receipt without signing twice', (tester) async {
    final repo = EditableReports(client);
    final shared = ApprovedSharedReports(repo)..commitThenThrow = true;
    await prepareV2Completion(tester, repo, shared);
    final finish = find.byKey(const ValueKey('daily-report-finish-approved-edit'));
    await reveal(tester, finish);
    await tester.tap(finish);
    await tester.pumpAndSettle();
    expect(shared.approvedWrites, 1);
    expect(find.text('日報の編集を完了しました。保存して確定しました。'), findsNothing);
    await tester.tap(finish);
    await tester.pumpAndSettle();
    expect(shared.approvedWrites, 1);
    expect(repo.signCalls, 0);
    expect(find.text('日報の編集を完了しました。保存して確定しました。'), findsOneWidget);
  });

  testWidgets('restored edit stages responsible signature and finalizes only on explicit completion',
    (tester) async {
      final repo = EditableReports(client);
      await prepareCompletion(tester, repo);
      expect(repo.signCalls, 0);
      final finish = find.byKey(const ValueKey('daily-report-finish-approved-edit'));
      await reveal(tester, finish);
      await tester.tap(finish);
      await tester.pumpAndSettle();
      expect(repo.signCalls, 1);
      expect(find.text('日報の編集を完了しました。保存して確定しました。'), findsOneWidget);
      expect(await DailyReportEditSessionStore().load('owner', 'report-a'), isNull);
    });

  testWidgets('lost response retains signature and retry reads committed report without signing twice',
    (tester) async {
      final repo = EditableReports(client)..commitThenThrow = true;
      await prepareCompletion(tester, repo);
      final finish = find.byKey(const ValueKey('daily-report-finish-approved-edit'));
      await reveal(tester, finish);
      await tester.tap(finish);
      await tester.pumpAndSettle();
      expect(repo.signCalls, 1);
      expect(find.text('日報の編集を完了しました。保存して確定しました。'), findsNothing);
      await tester.tap(finish);
      await tester.pumpAndSettle();
      expect(repo.signCalls, 1);
      expect(find.text('日報の編集を完了しました。保存して確定しました。'), findsOneWidget);
    });

  testWidgets('changed report text invalidates the staged responsible signature',
    (tester) async {
      final repo = EditableReports(client);
      await prepareCompletion(tester, repo);
      final description = find.byKey(const ValueKey('daily-report-work-description'));
      await reveal(tester, description);
      await tester.enterText(description, '変更した作業');
      await tester.pumpAndSettle();
      final finish = find.byKey(const ValueKey('daily-report-finish-approved-edit'));
      await reveal(tester, finish);
      expect(tester.widget<FilledButton>(finish).onPressed, isNull);
      expect(repo.signCalls, 0);
    });

  testWidgets('actor switch after signature capture cannot complete the old report',
    (tester) async {
      final repo = EditableReports(client);
      await prepareCompletion(tester, repo);
      repo.actor = 'another-user';
      final finish = find.byKey(const ValueKey('daily-report-finish-approved-edit'));
      await reveal(tester, finish);
      await tester.tap(finish);
      await tester.pumpAndSettle();
      expect(repo.signCalls, 0);
      expect(find.text('日報の編集を完了しました。保存して確定しました。'), findsNothing);
    });

  testWidgets('different consumed request cannot restore edit completion',
    (tester) async {
      final repo = EditableReports(client)
        ..signed = false ..approved = false ..reporterSigned = true;
      await DailyReportEditSessionStore().remember(const DailyReportEditSession(
        actorId: 'owner', companyId: 'company-a', reportId: 'report-a',
        requestId: 'different-request', confirmed: true));
      await open(tester, repo);
      expect(find.byKey(const ValueKey('daily-report-finish-approved-edit')), findsNothing);
      final tile = find.ancestor(of: find.text('責任者サイン'), matching: find.byType(ListTile));
      await reveal(tester, tile);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(find.byType(SignatureCapturePage), findsNothing);
      expect(repo.signCalls, 0);
    });

  testWidgets('ordinary draft without edit session keeps existing signing flow',
    (tester) async {
      final repo = EditableReports(client)
        ..signed = false ..approved = false ..reporterSigned = true;
      await open(tester, repo);
      expect(find.byKey(const ValueKey('daily-report-finish-approved-edit')), findsNothing);
      final tile = find.ancestor(of: find.text('責任者サイン'), matching: find.byType(ListTile));
      await reveal(tester, tile);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(SignatureCapturePage))).pop(
        const SignatureResult(signerName: '責任者', strokes: [[Offset(0.1, 0.2)]]));
      await tester.pumpAndSettle();
      expect(repo.signCalls, 1);
      expect(find.text('日報の編集を完了しました。保存して確定しました。'), findsNothing);
    });

  testWidgets('real reporter save precedes responsible staging and explicit completion',
    (tester) async {
      final repo = EditableReports(client);
      await open(tester, repo);
      await begin(tester);
      await tester.tap(find.text('編集を開始').last);
      await tester.pumpAndSettle();
      final reporterTile = find.ancestor(of: find.text('報告者サイン'),
        matching: find.byType(ListTile));
      await reveal(tester, reporterTile);
      await tester.tap(reporterTile);
      await tester.pumpAndSettle();
      expect(find.byType(SignatureCapturePage), findsOneWidget);
      Navigator.of(tester.element(find.byType(SignatureCapturePage))).pop(
        const SignatureResult(signerName: '報告者', strokes: [[Offset(0.2, 0.3)]]));
      await tester.pumpAndSettle();
      expect(repo.reporterCalls, 1);
      expect(repo.signCalls, 0);
      expect(repo.reporterSigned, isTrue);
      final responsibleTile = find.ancestor(of: find.text('責任者サイン'),
        matching: find.byType(ListTile));
      await reveal(tester, responsibleTile);
      await tester.tap(responsibleTile);
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(SignatureCapturePage))).pop(
        const SignatureResult(signerName: '責任者', strokes: [[Offset(0.7, 0.8)]]));
      await tester.pumpAndSettle();
      expect(repo.reporterCalls, 1);
      expect(repo.signCalls, 0);
      final finish = find.byKey(const ValueKey('daily-report-finish-approved-edit'));
      await reveal(tester, finish);
      await tester.tap(finish);
      await tester.pumpAndSettle();
      expect(repo.signCalls, 1);
      expect(repo.responsibleName, '責任者');
      expect(find.text('日報の編集を完了しました。保存して確定しました。'), findsOneWidget);
    });

  testWidgets('failed signature save keeps pending signature for a successful retry',
    (tester) async {
      final repo = EditableReports(client)..failSign = true;
      await prepareCompletion(tester, repo);
      final finish = find.byKey(const ValueKey('daily-report-finish-approved-edit'));
      await reveal(tester, finish);
      await tester.tap(finish);
      await tester.pumpAndSettle();
      expect(repo.signCalls, 1);
      expect(repo.signed, isFalse);
      expect(tester.widget<FilledButton>(finish).onPressed, isNotNull);
      expect(find.text('日報の編集を完了しました。保存して確定しました。'), findsNothing);
      repo.failSign = false;
      await tester.tap(finish);
      await tester.pumpAndSettle();
      expect(repo.signCalls, 2);
      expect(find.text('日報の編集を完了しました。保存して確定しました。'), findsOneWidget);
    });

}

// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:sk_works/features/attendance/paid_work_hours_repository.dart';
import 'package:sk_works/features/daily_reports/daily_report_page.dart';
import 'package:sk_works/features/daily_reports/daily_report_repository.dart';
import 'package:sk_works/features/daily_reports/shared_daily_report_repository.dart';
import 'package:sk_works/features/daily_reports/shared_worker_facts_repository.dart';
import 'package:sk_works/features/daily_reports/daily_report_company_allowance_selection.dart';
import 'package:sk_works/features/daily_reports/signature_capture_page.dart';
import 'package:sk_works/features/shared/company_allowance_label_repository.dart';

const _actor = '00000000-0000-0000-0000-000000000010';
const _company = '00000000-0000-0000-0000-000000000001';
const _worker = '00000000-0000-0000-0000-000000000020';
const _peer = '00000000-0000-0000-0000-000000000021';
const _report = '00000000-0000-0000-0000-000000000030';
const _site = '00000000-0000-0000-0000-000000000040';
const _source = '00000000-0000-0000-0000-000000000050';
const _scope = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
final _date = DateTime(2026, 10, 25);

class _Reports implements DailyReportRepository {
  bool reporterSaved = false, supervisorSaved = false, peerOpen = false;
  int draftWrites = 0, ordinaryReporterWrites = 0;
  List<DailyReportWorkerDraft> get workers => [
    DailyReportWorkerDraft(workerId: _worker, workerName: '報告者',
      sourceClockInId: _source, sourceClockOutAt: DateTime(2026, 10, 25, 17)),
    if (peerOpen) DailyReportWorkerDraft(workerId: _peer, workerName: '勤務継続中',
      sourceClockInId: '00000000-0000-0000-0000-000000000051'),
  ];
  @override String? get currentActorId => _actor;
  @override String? get notificationRetryUserId => null;
  @override Future<List<DailyReportSiteGroup>> loadClockedInGroups(DateTime date) async => [
    DailyReportSiteGroup(siteId: _site, siteName: '対象現場', workers: workers),
  ];
  @override Future<DailyReportRecord?> loadReport({required DateTime date,
    String? siteId, String? routeAssignmentId, String? vehicleClockInAnchorId,
    String? reportId}) async => DailyReportRecord(id: _report, companyId: _company,
      date: date, siteId: _site, siteName: '対象現場', workDescription: '保存済みの作業',
      status: supervisorSaved ? 'signed' : 'draft', workers: workers,
      reporterSignerName: reporterSaved ? '最初の報告者' : null,
      reporterSignatureJson: reporterSaved ? {'strokes': [[{'x': 0.1, 'y': 0.2}]]} : null,
      responsibleSignerName: supervisorSaved ? '責任者' : null,
      responsibleSignatureJson: supervisorSaved ? {'strokes': [[{'x': 0.1, 'y': 0.2}]]} : null);
  @override Future<List<DailyReportEvidenceRecord>> loadAttendanceEvidence({String? reportId,
    required DateTime date, String? siteId, String? routeAssignmentId}) async => [];
  @override Future<bool> vehicleMeterEnabledForAnchor(String? anchor) async => false;
  @override Future<CompanyAllowanceLabelSnapshot> loadCompanyAllowanceLabels({
    required Iterable<String> workerIds, String? expectedCompanyId}) async =>
      const CompanyAllowanceLabelSnapshot(companyId: _company, version: 1, items: []);
  @override Future<bool> hasApprovedEdit(String reportId) async => false;
  @override Future<String> loadResponsibleName({String? siteId, String? routeAssignmentId}) async => '責任者';
  @override Future<String> saveDraft({String? reportId, String? siteId,
    String? routeAssignmentId, required DateTime date, required String workDescription,
    required List<DailyReportWorkerDraft> workers, String? groupClockInAnchorId,
    String? vehicleClockInAnchorId}) async { draftWrites++; return _report; }
  @override Future<void> saveReporterSignature({required String reportId,
    required String signerName, required Object signatureJson}) async { ordinaryReporterWrites++; }
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Hours implements PaidWorkHoursRepository {
  bool required = false, fail = false, versionTwo = false;
  final workersRead = <String>[];
  @override Future<PaidWorkHoursSnapshot> load({required String companyId,
    required String workerId, required String reportId}) async {
    workersRead.add(workerId);
    if (fail) throw StateError('hours API unavailable');
    return PaidWorkHoursSnapshot(actorId: _actor, companyId: companyId,
      workerId: workerId, reportId: reportId, workDate: _date, revision: 0,
      scopeFingerprint: _scope, hoursRequired: required, editable: false,
      sourceBlocked: false, inputScopeCurrent: true, sourceReasons: [],
      contractVersion: versionTwo ? 2 : 1, firstReporterCoversWorkOnly: versionTwo,
      workBasisHash: versionTwo ? _scope : null);
  }
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _Shared implements SharedDailyReportRepository {
  _Shared(this.reports, {this.enabled = true});
  final _Reports reports;
  final bool enabled;
  int supervisorWrites = 0;
  SharedDailyReportContext get state => SharedDailyReportContext(actorId: _actor,
    companyId: _company, workerId: _worker, reportId: _report, sourceClockInId: _source,
    clockOutId: '00000000-0000-0000-0000-000000000060', workDate: _date,
    state: !enabled ? 'disabled' : reports.supervisorSaved ? 'supervisor_saved' :
      reports.reporterSaved ? 'reporter_saved_waiting_supervisor' : 'reporter_required',
    enabled: enabled, canManageAttendance: false, reporterSaved: reports.reporterSaved,
    supervisorSaved: reports.supervisorSaved, sourceAttached: true,
    reporterName: reports.reporterSaved ? '最初の報告者' : '',
    reportStatus: reports.supervisorSaved ? 'signed' : 'draft',
    expectedUpdatedAt: DateTime.utc(2026, 10, 25, 8), signatureScopeFingerprint: _scope,
    firstReporterCoversWorkOnly: enabled,
    workBasis: {'contract_version': 2, 'report': {'id': _report, 'company_id': _company,
      'work_date': '2026-10-25', 'site_id': _site, 'route_assignment_id': null,
      'work_description': '保存済みの作業'},
      'roster': [for (final worker in reports.workers) {'worker_id': worker.workerId}]});
  @override Future<SharedDailyReportContext> loadReport(String reportId, {String? expectedActor}) async => state;
  @override Future<SharedDailyReportContext> collectSupervisor({required SharedDailyReportContext before,
    required String signerName, required Map<String, dynamic> signature}) async {
    expect(before.signatureScopeFingerprint, _scope);
    expect(signature['strokes'], isA<List>());
    supervisorWrites++;
    reports.supervisorSaved = true;
    return state;
  }
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Facts implements SharedWorkerFactsRepository {
  bool requireHours = true, managePeer = false;
  bool? outsideCurrentReport;
  int confirmations = 0;
  SharedWorkerFacts? savedFacts;
  double? savedHours;
  String? reason;
  SharedWorkerFacts proposed() => SharedWorkerFacts(overtimeHours: 0, earlyHours: 0,
    nightHours: 0, workCategory: 'day', allowanceAmount: 0, allowanceLabel: null,
    companyAllowanceSelections: DailyReportCompanyAllowanceSelections([]),
    legacyLabels: null, vehicleId: null, routeId: null, odometerKm: null);
  SharedWorkerFactsSnapshot snapshot(String workerId) => SharedWorkerFactsSnapshot(
    scope: PaidWorkHoursSnapshot(actorId: _actor, companyId: _company,
      workerId: workerId, reportId: _report, workDate: _date,
      revision: savedFacts == null ? 0 : 1, scopeFingerprint: _scope,
      hoursRequired: requireHours, editable: workerId == _worker,
      sourceBlocked: false, inputScopeCurrent: true, sourceReasons: [],
      hours: savedHours, contractVersion: 2, workReportFrozen: true,
      firstReporterCoversWorkOnly: true, workBasisHash: _scope),
    facts: savedFacts, proposedFacts: proposed(),
    confirmed: savedFacts != null, current: savedFacts != null,
    isOwnWorker: workerId == _worker, canManageAttendance: managePeer && workerId == _peer,
    hoursRequiredOutsideCurrentReport: outsideCurrentReport ?? requireHours);
  @override Future<SharedWorkerFactsSnapshot> load({required String companyId,
    required String reportId, required String workerId}) async => snapshot(workerId);
  @override Future<SharedWorkerFactsSnapshot> confirm(SharedWorkerFactsSnapshot before,
    SharedWorkerFacts facts, {double? hours, String? managementReason}) async {
    confirmations++;
    savedFacts = facts;
    savedHours = hours;
    reason = managementReason;
    return snapshot(before.workerId);
  }
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() {
    final previous = SharedPreferencesAsyncPlatform.instance;
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    addTearDown(() => SharedPreferencesAsyncPlatform.instance = previous);
  });
  Future<void> open(WidgetTester tester, _Reports reports, _Hours hours, _Shared shared, {_Facts? facts}) async {
    await tester.pumpWidget(MaterialApp(home: DailyReportPage(initialDate: _date,
      initialSiteId: _site, initialReportId: _report, repositoryForTesting: reports,
      paidHoursRepositoryForTesting: hours, sharedReportRepositoryForTesting: shared,
      workerFactsRepositoryForTesting: facts)));
    await tester.pumpAndSettle();
  }
  Future<void> reveal(WidgetTester tester, String text) async {
    final finder = find.text(text).first;
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(finder, 220, scrollable: scrollable, maxScrolls: 40);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('saved shared reporter facts are read-only and opening never rewrites the report', (tester) async {
    final reports = _Reports()..reporterSaved = true;
    await open(tester, reports, _Hours(), _Shared(reports));
    expect(find.text('最初の報告者さんが日報を登録しました'), findsOneWidget);
    final description = find.byKey(const ValueKey('daily-report-work-description'));
    await tester.scrollUntilVisible(description, 200, scrollable: find.byType(Scrollable).first);
    expect(tester.widget<TextField>(description).enabled, isFalse);
    await reveal(tester, '報告者サイン');
    final tile = tester.widget<ListTile>(find.ancestor(of: find.text('報告者サイン'), matching: find.byType(ListTile)));
    expect(tile.onTap, isNull);
    expect(find.text('登録'), findsNothing);
    expect(reports.draftWrites, 0);
    expect(reports.ordinaryReporterWrites, 0);
  });
  for (final unavailable in [false, true]) {
    testWidgets('missing or unavailable hours cannot open a legacy reporter signature ($unavailable)', (tester) async {
      final reports = _Reports();
      final hours = _Hours()..required = true..fail = unavailable;
      await open(tester, reports, hours, _Shared(reports, enabled: false));
      await reveal(tester, '報告者サイン');
      await tester.tap(find.text('報告者サイン'));
      await tester.pumpAndSettle();
      expect(find.byType(SignatureCapturePage), findsNothing);
      expect(reports.ordinaryReporterWrites, 0);
      expect(hours.workersRead, contains(_worker));
    });
  }
  testWidgets('explicit v2 work-only first report can open its signature while a peer remains working', (tester) async {
    final reports = _Reports()..peerOpen = true;
    final hours = _Hours()..required = true..versionTwo = true;
    await open(tester, reports, hours, _Shared(reports));
    await reveal(tester, '報告者サイン');
    await tester.tap(find.text('報告者サイン'));
    await tester.pumpAndSettle();
    expect(find.byType(SignatureCapturePage), findsOneWidget);
    expect(hours.workersRead.toSet(), containsAll([_worker, _peer]));
    expect(reports.ordinaryReporterWrites, 0);
    await tester.pageBack();
    await tester.pumpAndSettle();
  });
  testWidgets('supervisor capture waits for server-ready personal facts and shows the frozen report', (tester) async {
    final reports = _Reports()..reporterSaved = true..peerOpen = true;
    final shared = _Shared(reports);
    await open(tester, reports, _Hours()..versionTwo = true, shared);
    await reveal(tester, '責任者サイン');
    await tester.tap(find.text('責任者サイン'));
    await tester.pumpAndSettle();
    expect(find.text('責任者サインの前に確認が必要です'), findsOneWidget);
    expect(find.text('保存済みの作業'), findsWidgets);
    expect(find.text('この内容で責任者サインへ'), findsNothing);
    expect(find.byType(SignatureCapturePage), findsNothing);
    expect(shared.supervisorWrites, 0);
    expect(reports.draftWrites, 0);
    await tester.tap(find.text('閉じる'));
    await tester.pumpAndSettle();
  });
  testWidgets('facts candidates never confirm themselves and missing hours never become zero', (tester) async {
    final reports = _Reports()..reporterSaved = true;
    final facts = _Facts();
    await open(tester, reports, _Hours(), _Shared(reports), facts: facts);
    expect(facts.confirmations, 0);
    final button = find.byKey(const ValueKey('confirm-worker-facts/$_worker'));
    await tester.scrollUntilVisible(button, 220, scrollable: find.byType(Scrollable).first, maxScrolls: 40);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(facts.confirmations, 0);
    final hours = find.byWidgetPredicate((widget) => widget is TextField &&
      widget.decoration?.labelText == '実勤務時間（休憩を除く）');
    await tester.ensureVisible(hours);
    await tester.enterText(hours, '7.25');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(facts.confirmations, 1);
    expect(facts.savedHours, 7.25);
    expect(facts.savedFacts?.allowanceAmount, 0);
    expect(reports.draftWrites, 0);
    expect(reports.ordinaryReporterWrites, 0);
  });
  testWidgets('clearing an actual overtime field blocks confirmation rather than silently storing zero', (tester) async {
    final reports = _Reports()..reporterSaved = true;
    final facts = _Facts()..requireHours = false;
    await open(tester, reports, _Hours(), _Shared(reports), facts: facts);
    final overtime = find.byWidgetPredicate((widget) => widget is TextField && widget.decoration?.labelText == '残業(h)');
    await tester.scrollUntilVisible(overtime, 220, scrollable: find.byType(Scrollable).first, maxScrolls: 40);
    await tester.enterText(overtime, '');
    final button = find.byKey(const ValueKey('confirm-worker-facts/$_worker'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(facts.confirmations, 0);
    expect(find.textContaining('残業時間を0〜24'), findsOneWidget);
    expect(reports.draftWrites, 0);
  });
  testWidgets('prospective no-hour choices do not reuse the previous target hour quantity', (tester) async {
    final reports = _Reports()..reporterSaved = true;
    final facts = _Facts()..outsideCurrentReport = false;
    await open(tester, reports, _Hours(), _Shared(reports), facts: facts);
    final button = find.byKey(const ValueKey('confirm-worker-facts/$_worker'));
    await tester.scrollUntilVisible(button, 220, scrollable: find.byType(Scrollable).first, maxScrolls: 40);
    expect(find.byWidgetPredicate((widget) => widget is TextField &&
      widget.decoration?.labelText == '実勤務時間（休憩を除く）'), findsNothing);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(facts.confirmations, 1);
    expect(facts.savedHours, isNull);
    expect(reports.draftWrites, 0);
  });
}

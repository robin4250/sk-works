// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:sk_works/features/attendance/paid_work_hours_repository.dart';
import 'package:sk_works/features/attendance/paid_work_hours_report_section.dart';
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
  bool omitSource = false, staleSupervisorRead = false, missingReport = false;
  bool recoveryChoices = false, documentMode = false;
  String description = '保存済みの作業';
  bool get persistedSupervisor => supervisorSaved && !staleSupervisorRead;
  int draftWrites = 0, ordinaryReporterWrites = 0;
  List<DailyReportWorkerDraft> get workers => [
    DailyReportWorkerDraft(workerId: _worker, workerName: '報告者',
      companyAllowanceSelections: recoveryChoices ? DailyReportCompanyAllowanceSelections([]) : null,
      sourceClockInId: omitSource ? null : _source, sourceClockOutAt: DateTime(2026, 10, 25, 17)),
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
    String? reportId}) async => missingReport ? null : DailyReportRecord(id: _report, companyId: _company,
      date: date, siteId: _site, siteName: '対象現場', workDescription: description,
      status: persistedSupervisor && !documentMode ? 'signed' : 'draft', workers: workers,
      reporterSignerName: reporterSaved ? '最初の報告者' : null,
      reporterSignatureJson: reporterSaved ? {'strokes': [[{'x': 0.1, 'y': 0.2}]]} : null,
      responsibleSignerName: persistedSupervisor ? '責任者' : null,
      responsibleSignatureJson: persistedSupervisor ? {'strokes': [[{'x': 0.1, 'y': 0.2}]]} : null);
  @override Future<List<DailyReportEvidenceRecord>> loadAttendanceEvidence({String? reportId,
    required DateTime date, String? siteId, String? routeAssignmentId}) async => [];
  @override Future<List<DailyReportWorkerDraft>> loadAnchoredWorkers({required String anchorId,
    required DateTime workDate, required List<DailyReportWorkerDraft> existing,
    required List<DailyReportWorkerDraft> fallback, required bool allowNewMembers}) async => existing;
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
  bool hold = false, manager = false, financialSupported = false, prepared = false, preparedValid = true;
  int financialPreparations = 0;
  List<SharedWorkerFactsTransitionInput>? financialInputs;
  String source = _source;
  bool workOnly = true, ready = false, documentOnly = false;
  int documentEdits = 0, documentSaves = 0;
  int supervisorWrites = 0;
  SharedDailyReportContext get state => SharedDailyReportContext(actorId: _actor,
    companyId: _company, workerId: _worker, reportId: _report, sourceClockInId: source,
    clockOutId: '00000000-0000-0000-0000-000000000060', workDate: _date,
    state: hold ? 'managed_financial_hold' : !enabled ? 'disabled' : reports.supervisorSaved ? 'supervisor_saved' :
      reports.reporterSaved ? 'reporter_saved_waiting_supervisor' : 'reporter_required',
    enabled: enabled, canManageAttendance: manager, reporterSaved: reports.reporterSaved,
    supervisorSaved: reports.supervisorSaved, sourceAttached: true,
    reporterName: reports.reporterSaved ? '最初の報告者' : '',
    reportStatus: reports.supervisorSaved ? 'signed' : 'draft',
    expectedUpdatedAt: DateTime.utc(2026, 10, 25, 8), signatureScopeFingerprint: _scope,
    supervisorReady: ready || (documentOnly && reports.reporterSaved && !reports.supervisorSaved),
    documentOnly: documentOnly, documentComplete: documentOnly && reports.persistedSupervisor,
    documentEditable: documentOnly && reports.reporterSaved,
    financialConfirmationRequired: documentOnly,
    financialResigningSupported: financialSupported && documentOnly,
    financialTransitionId: prepared ? 7 : null, financialTransitionValid: prepared && preparedValid,
    documentBasis: documentOnly ? {'report': {'id': _report, 'company_id': _company, 'report_date': '2026-10-25',
      'work_description': reports.description}, 'workers': [for (final w in reports.workers) {
      'report_id': _report, 'worker_id': w.workerId, 'worker_name': w.workerName,
      'overtime_hours': w.overtimeHours, 'early_hours': w.earlyHours, 'night_hours': w.nightHours,
      'allowance_amount': w.allowanceAmount, 'allowance_label': w.allowanceLabel,
      'company_allowance_selections': w.companyAllowanceSelections?.toJson(),
      'vehicle_id': w.vehicleId, 'route_assignment_id': w.routeId, 'odometer_km': w.odometerKm}]} : null,
    firstReporterCoversWorkOnly: enabled && workOnly,
    workBasis: {'contract_version': 2, 'report': {'id': _report, 'company_id': _company,
      'work_date': '2026-10-25', 'site_id': _site, 'route_assignment_id': null,
      'work_description': '保存済みの作業'},
      'roster': [for (final worker in reports.workers) {'worker_id': worker.workerId}]});
  @override Future<SharedDailyReportContext> loadForSource(String sourceClockInId) async => state;
  @override Future<SharedDailyReportContext> loadReport(String reportId, {String? expectedActor}) async => state;
  @override Future<SharedDailyReportContext> collectSupervisor({required SharedDailyReportContext before,
    required String signerName, required Map<String, dynamic> signature}) async {
    expect(before.signatureScopeFingerprint, _scope);
    expect(signature['strokes'], isA<List>());
    supervisorWrites++;
    reports.supervisorSaved = true;
    return state;
  }
  @override Future<SharedDailyReportContext> prepareFinancialResigning({required SharedDailyReportContext before,
    required List<SharedWorkerFactsTransitionInput> workers, required String reason}) async {
    expect(before.reporterSaved, isFalse); expect(before.supervisorSaved, isFalse);
    expect(reason, isNotEmpty); expect(workers.single.before.actorId, _actor);
    financialPreparations++; financialInputs = workers;
    prepared = true; documentOnly = false; reports.documentMode = false;
    return state;
  }
  @override Future<SharedDailyReportContext> saveDocumentDraft({required SharedDailyReportContext before,
    required String workDescription, required List<Map<String, dynamic>> workers}) async {
    expect(before.documentOnly, isTrue);
    expect(before.reporterSaved, isFalse);
    expect(workers.single['worker_id'], _worker);
    documentSaves++;
    reports.description = workDescription;
    return state;
  }
  @override Future<SharedDailyReportContext> startDocumentEdit({required SharedDailyReportContext before,
    required String reason}) async {
    expect(before.documentEditable, isTrue);
    expect(reason, isNotEmpty);
    documentEdits++;
    reports.reporterSaved = false;
    reports.supervisorSaved = false;
    return state;
  }
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MissingShared extends _Shared {
  _MissingShared(super.reports, this.phase);
  final String phase;
  @override SharedDailyReportContext get state => SharedDailyReportContext(
    actorId: _actor, companyId: _company, workerId: _worker,
    sourceClockInId: _source, workDate: _date, state: phase,
    enabled: phase != 'disabled', canManageAttendance: false,
    reporterSaved: false, supervisorSaved: false, sourceAttached: false);
}

class _Facts implements SharedWorkerFactsRepository {
  bool requireHours = true, managePeer = false, manageAll = false, frozen = true;
  bool? outsideCurrentReport;
  int confirmations = 0, reads = 0;
  bool missingProposal = false;
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
      hours: savedHours, contractVersion: 2, workReportFrozen: frozen,
      firstReporterCoversWorkOnly: true, workBasisHash: _scope),
    facts: savedFacts, proposedFacts: missingProposal ? null : proposed(),
    confirmed: savedFacts != null, current: savedFacts != null,
    isOwnWorker: workerId == _worker, canManageAttendance: manageAll || managePeer && workerId == _peer,
    hoursRequiredOutsideCurrentReport: outsideCurrentReport ?? requireHours);
  @override Future<SharedWorkerFactsSnapshot> load({required String companyId,
    required String reportId, required String workerId}) async { reads++; return snapshot(workerId); }
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
    final finder = find.text(text);
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(finder, 220, scrollable: scrollable, maxScrolls: 40);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('financial capability unavailable preserves both actual signatures', (tester) async {
    final reports = _Reports()..reporterSaved = true..supervisorSaved = true..documentMode = true;
    final shared = _Shared(reports)..documentOnly = true..manager = true;
    await open(tester, reports, _Hours(), shared, facts: _Facts());
    await reveal(tester, '勤務実績を確認して給与・請求へ進む');
    await tester.tap(find.byKey(const ValueKey('daily-report-financial-resigning')));
    await tester.pumpAndSettle();
    expect(shared.documentEdits, 0); expect(shared.financialPreparations, 0);
    expect(reports.reporterSaved, isTrue); expect(reports.supervisorSaved, isTrue);
    expect(find.textContaining('勤務実績の連携は準備中'), findsOneWidget);
  });
  testWidgets('explicit category batch stages facts only then actual new reporter capture without old writer', (tester) async {
    final reports = _Reports()..reporterSaved = true..supervisorSaved = true..documentMode = true..recoveryChoices = true;
    final shared = _Shared(reports)..documentOnly = true..manager = true..financialSupported = true;
    final facts = _Facts()..manageAll = true..missingProposal = true..requireHours = false..frozen = false;
    await open(tester, reports, _Hours()..versionTwo = true, shared, facts: facts);
    await reveal(tester, '勤務実績を確認して給与・請求へ進む');
    await tester.tap(find.byKey(const ValueKey('daily-report-financial-resigning')));
    await tester.pumpAndSettle();
    expect(shared.documentEdits, 0);
    await tester.tap(find.text('履歴に残して確認を始める'));
    await tester.pumpAndSettle();
    expect(shared.documentEdits, 1); expect(reports.reporterSaved, isFalse);
    await reveal(tester, 'この人の勤務実績を確認');
    await tester.tap(find.text('この人の勤務実績を確認'));
    await tester.pumpAndSettle();
    expect(find.text('勤務区分（日勤・夜勤など）を選んでください。'), findsOneWidget);
    expect(shared.financialPreparations, 0); expect(facts.confirmations, 0);
    final category = find.byType(DropdownButtonFormField<String>).last;
    await tester.ensureVisible(category); await tester.tap(category); await tester.pumpAndSettle();
    await tester.tap(find.text('夜勤').last); await tester.pumpAndSettle();
    await reveal(tester, 'この人の勤務実績を確認');
    await tester.tap(find.text('この人の勤務実績を確認')); await tester.pumpAndSettle();
    expect(find.text('1 / 1 人の内容を確認済み'), findsOneWidget);
    // Any subsequent change must invalidate that person's explicit review.
    await tester.ensureVisible(category); await tester.tap(category); await tester.pumpAndSettle();
    await tester.tap(find.text('日勤').last); await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('prepare-financial-resigning'))).onPressed, isNull);
    await tester.tap(category); await tester.pumpAndSettle();
    await tester.tap(find.text('夜勤').last); await tester.pumpAndSettle();
    await reveal(tester, 'この人の勤務実績を確認');
    await tester.tap(find.text('この人の勤務実績を確認')); await tester.pumpAndSettle();
    await reveal(tester, '確認した勤務実績を保存してサインへ');
    await tester.enterText(find.byKey(const ValueKey('financial-transition-reason')), '実際の夜勤と適用手当を管理者が確認');
    await tester.ensureVisible(find.byKey(const ValueKey('prepare-financial-resigning')));
    await tester.tap(find.byKey(const ValueKey('prepare-financial-resigning'))); await tester.pumpAndSettle();
    expect(shared.financialPreparations, 1); expect(shared.financialInputs!.single.facts.workCategory, 'night');
    expect(facts.confirmations, 0); expect(reports.draftWrites, 0); expect(shared.documentSaves, 0);
    expect(reports.reporterSaved, isFalse); expect(reports.supervisorSaved, isFalse);
    await reveal(tester, '報告者サイン'); await tester.tap(find.text('報告者サイン').first);
    await tester.pumpAndSettle();
    expect(find.byType(SignatureCapturePage), findsOneWidget); expect(reports.draftWrites, 0);
  });
  for (final valid in [false, true]) {
    testWidgets('reopened staged report avoids old draft writer, valid=$valid', (tester) async {
      final reports = _Reports();
      final shared = _Shared(reports)..prepared = true..preparedValid = valid;
      await open(tester, reports, _Hours()..versionTwo = true, shared, facts: _Facts());
      await reveal(tester, '報告者サイン'); await tester.tap(find.text('報告者サイン').first);
      await tester.pumpAndSettle();
      expect(reports.draftWrites, 0); expect(shared.documentSaves, 0);
      expect(find.byType(SignatureCapturePage), valid ? findsOneWidget : findsNothing);
    });
  }

  testWidgets('missing category proposal permits explicit confirmation without replacing reporter signature', (tester) async {
    final reports = _Reports()..reporterSaved = true..recoveryChoices = true;
    final facts = _Facts()..missingProposal = true..requireHours = false;
    await open(tester, reports, _Hours(), _Shared(reports), facts: facts);
    await reveal(tester, 'この勤務実績を確認して保存');
    await tester.tap(find.text('この勤務実績を確認して保存'));
    await tester.pumpAndSettle();
    expect(find.text('勤務区分（日勤・夜勤など）を選んでください。'), findsOneWidget);
    expect(facts.confirmations, 0);
    final category = find.byType(DropdownButtonFormField<String>).last;
    await tester.ensureVisible(category);
    await tester.tap(category);
    await tester.pumpAndSettle();
    await tester.tap(find.text('日勤').last);
    await tester.pumpAndSettle();
    await reveal(tester, 'この勤務実績を確認して保存');
    await tester.tap(find.text('この勤務実績を確認して保存'));
    await tester.pumpAndSettle();
    expect(facts.confirmations, 1);
    expect(facts.savedFacts!.workCategory, 'day');
    expect(reports.draftWrites, 0);
    expect(reports.ordinaryReporterWrites, 0);
    expect(reports.reporterSaved, isTrue);
  });

  for (final stale in [false, true]) {
    testWidgets('document-only supervisor goes straight to signature without personal-facts save, stale=$stale', (tester) async {
      final reports = _Reports()..reporterSaved = true..documentMode = true..staleSupervisorRead = stale;
      final shared = _Shared(reports)..documentOnly = true;
      final hours = _Hours()..fail = true;
      final facts = _Facts()..missingProposal = true;
      await open(tester, reports, hours, shared, facts: facts);
      expect(facts.reads, 0);
      await reveal(tester, '責任者サイン');
      await tester.tap(find.text('責任者サイン'));
      await tester.pumpAndSettle();
      expect(find.byType(SignatureCapturePage), findsOneWidget);
      expect(find.text('この内容で責任者サインへ'), findsNothing);
      expect(hours.workersRead, isEmpty);
      expect(facts.reads, 0);
      expect(reports.draftWrites, 0);
      expect(find.byTooltip('サインする日報を確認'), findsOneWidget);
      Navigator.of(tester.element(find.byType(SignatureCapturePage))).pop(
        const SignatureResult(signerName: '責任者', strokes: [[Offset(0.1, 0.2)]]));
      await tester.pumpAndSettle();
      expect(shared.supervisorWrites, 1);
      expect(find.text('責任者サインを保存し、日報が完了しました'), stale ? findsNothing : findsOneWidget);
      expect(reports.draftWrites, 0);
      expect(reports.ordinaryReporterWrites, 0);
    });
  }
  for (final supervisorSigned in [false, true]) {
    testWidgets('document hand-edit clears visible signatures only after explicit server reset, supervisor=$supervisorSigned', (tester) async {
      final reports = _Reports()..reporterSaved = true..documentMode = true..supervisorSaved = supervisorSigned;
      final shared = _Shared(reports)..documentOnly = true;
      await open(tester, reports, _Hours(), shared);
      await reveal(tester, '手直し');
      await tester.tap(find.text('手直し'));
      await tester.pumpAndSettle();
      expect(shared.documentEdits, 0);
      await tester.tap(find.text('戻る'));
      await tester.pumpAndSettle();
      expect(reports.reporterSaved, isTrue);
      await reveal(tester, '手直し');
      await tester.tap(find.text('手直し'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('手直しを始める'));
      await tester.pumpAndSettle();
      expect(shared.documentEdits, 1);
      expect(reports.reporterSaved, isFalse);
      expect(reports.supervisorSaved, isFalse);
      expect(reports.draftWrites, 0);
      expect(find.text('日報を手直しできます。保存後にサインを取り直してください。'), findsOneWidget);
    });
  }

  testWidgets('document correction saves changed text through document writer without legacy roster rewrite', (tester) async {
    final reports = _Reports()..reporterSaved = true..documentMode = true;
    final shared = _Shared(reports)..documentOnly = true;
    await open(tester, reports, _Hours(), shared);
    await reveal(tester, '手直し');
    await tester.tap(find.text('手直し'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('手直しを始める'));
    await tester.pumpAndSettle();
    final description = find.byKey(const ValueKey('daily-report-work-description'));
    await tester.ensureVisible(description);
    await tester.enterText(description, '手直しした作業内容');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await reveal(tester, '登録');
    await tester.tap(find.text('登録'));
    await tester.pumpAndSettle();
    expect(shared.documentSaves, 1);
    expect(reports.description, '手直しした作業内容');
    expect(reports.draftWrites, 0);
    expect(reports.reporterSaved, isFalse);
    expect(reports.supervisorSaved, isFalse);
  });

  test('report guidance removes technical StateError wrapper', () {
    expect(dailyReportActionErrorMessage(StateError('日報を再読み込みしてください。')),
      '日報を再読み込みしてください。');
    expect(dailyReportActionErrorMessage(Exception('shared_report_reporter_signature_required')),
      '先に報告者サインを登録してください。');
    expect(dailyReportActionErrorMessage(Exception('private network details')),
      isNot(contains('private network details')));
  });

  testWidgets('blank description explains required input before saving or opening signature', (tester) async {
    final reports = _Reports();
    await open(tester, reports, _Hours(), _Shared(reports));
    final description = find.byKey(const ValueKey('daily-report-work-description'));
    await tester.ensureVisible(description);
    await tester.enterText(description, '   ');
    await reveal(tester, '報告者サイン');
    await tester.tap(find.text('報告者サイン'));
    await tester.pumpAndSettle();
    expect(find.text('作業内容を入力してから報告者サインへ進んでください。'), findsOneWidget);
    expect(find.byType(SignatureCapturePage), findsNothing);
    expect(reports.draftWrites, 0);
    expect(reports.ordinaryReporterWrites, 0);
  });

  for (final phase in ['report_missing', 'own_checkout_required', 'source_conflict', 'disabled']) {
    testWidgets('new individual report accepts only verified report_missing source ($phase)', (tester) async {
      final reports = _Reports()..missingReport = true..omitSource = true;
      await tester.pumpWidget(MaterialApp(home: DailyReportPage(
        initialDate: _date, initialSiteId: _site,
        vehicleClockInId: _source, groupClockInAnchorId: _source,
        restrictedReporterRegistration: true, registrationActorId: _actor,
        registrationCompanyId: _company, registrationWorkerId: _worker,
        repositoryForTesting: reports, paidHoursRepositoryForTesting: _Hours(),
        sharedReportRepositoryForTesting: _MissingShared(reports, phase))));
      await tester.pumpAndSettle();
      expect(find.textContaining('退勤した本人の勤務原本を確認できません'),
        phase == 'report_missing' ? findsNothing : findsOneWidget);
      expect(reports.draftWrites, 0);
      expect(reports.ordinaryReporterWrites, 0);
      expect(reports.workers.single.sourceClockInId, isNull);
    });
  }

  for (final valid in [true, false]) {
    testWidgets('restricted saved report uses verified shared source, match=$valid', (tester) async {
      final reports = _Reports()..reporterSaved = true..omitSource = true;
      final shared = _Shared(reports);
      if (!valid) shared.source = '00000000-0000-0000-0000-000000000099';
      await tester.pumpWidget(MaterialApp(home: DailyReportPage(
        initialDate: _date, initialSiteId: _site, initialReportId: _report,
        vehicleClockInId: _source, groupClockInAnchorId: _source,
        restrictedReporterRegistration: true, registrationActorId: _actor,
        registrationCompanyId: _company, registrationWorkerId: _worker,
        repositoryForTesting: reports, paidHoursRepositoryForTesting: _Hours(),
        sharedReportRepositoryForTesting: shared)));
      await tester.pumpAndSettle();
      expect(find.textContaining('退勤した本人の勤務原本を確認できません'),
        valid ? findsNothing : findsOneWidget);
      if (valid) expect(find.text('最初の報告者さんが日報を登録しました'), findsOneWidget);
      expect(reports.draftWrites, 0);
      expect(reports.ordinaryReporterWrites, 0);
      expect(reports.workers.first.sourceClockInId, isNull);
    });
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
  testWidgets('financial hold blocks draft and signature edits without retrying writes', (tester) async {
    final reports = _Reports();
    await open(tester, reports, _Hours(), _Shared(reports)..hold = true);
    expect(find.textContaining('手入力済み勤怠・給与との差異'), findsOneWidget);
    expect(find.text('登録'), findsNothing);
    await reveal(tester, '報告者サイン');
    final tile = tester.widget<ListTile>(find.ancestor(of: find.text('報告者サイン'), matching: find.byType(ListTile)));
    expect(tile.onTap, isNull);
    expect(find.byType(SignatureCapturePage), findsNothing);
    expect(reports.draftWrites, 0);
    expect(reports.ordinaryReporterWrites, 0);
  });
  testWidgets('a signed legacy shared report retains its original hours editor', (tester) async {
    final reports = _Reports()..reporterSaved = true;
    final hours = _Hours()..required = true;
    await open(tester, reports, hours, _Shared(reports)..workOnly = false);
    final section = find.byType(PaidWorkHoursReportSection);
    await tester.scrollUntilVisible(section, 220, scrollable: find.byType(Scrollable).first, maxScrolls: 40);
    await tester.pumpAndSettle();
    expect(section, findsOneWidget);
    expect(hours.workersRead, contains(_worker));
    expect(find.text('本人の勤務実績を確認'), findsNothing);
    expect(reports.draftWrites, 0);
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
  for (final staleRead in [false, true]) {
    testWidgets('restricted supervisor signs only server-ready facts and verifies persisted final state stale=$staleRead', (tester) async {
      final reports = _Reports()..reporterSaved = true..omitSource = true
        ..staleSupervisorRead = staleRead;
      final shared = _Shared(reports)..ready = true;
      var notified = 0;
      await tester.pumpWidget(MaterialApp(home: DailyReportPage(
        initialDate: _date, initialSiteId: _site, initialReportId: _report,
        vehicleClockInId: _source, groupClockInAnchorId: _source,
        restrictedReporterRegistration: true, registrationActorId: _actor,
        registrationCompanyId: _company, registrationWorkerId: _worker,
        onRegistrationSaved: () => notified++, repositoryForTesting: reports,
        paidHoursRepositoryForTesting: _Hours()..versionTwo = true,
        sharedReportRepositoryForTesting: shared)));
      await tester.pumpAndSettle();
      await reveal(tester, '責任者サイン');
      await tester.tap(find.text('責任者サイン'));
      await tester.pumpAndSettle();
      expect(find.text('責任者サインで確認する内容'), findsOneWidget);
      await tester.tap(find.text('この内容で責任者サインへ'));
      await tester.pumpAndSettle();
      expect(find.byType(SignatureCapturePage), findsOneWidget);
      // Synthetic isolated UI result only; no production signature is created.
      Navigator.of(tester.element(find.byType(SignatureCapturePage))).pop(
        const SignatureResult(signerName: '責任者', strokes: [[Offset(0.1, 0.2)]]));
      await tester.pumpAndSettle();
      expect(shared.supervisorWrites, 1);
      expect(reports.draftWrites, 0);
      expect(find.text('責任者サインで日報を確定しました'), staleRead ? findsNothing : findsOneWidget);
      if (staleRead) expect(find.textContaining('保存・確定を再確認できませんでした'), findsOneWidget);
      if (!staleRead) expect(notified, greaterThan(0));
    });
  }

  testWidgets('facts candidates never confirm themselves and missing hours never become zero', (tester) async {
    final reports = _Reports()..reporterSaved = true;
    final facts = _Facts();
    await open(tester, reports, _Hours(), _Shared(reports), facts: facts);
    expect(facts.confirmations, 0);
    final button = find.byKey(const ValueKey('confirm-worker-facts/$_worker'));
    await tester.scrollUntilVisible(button, 220, scrollable: find.byType(Scrollable).first, maxScrolls: 40);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(facts.confirmations, 0);
    final hours = find.byWidgetPredicate((widget) => widget is TextField &&
      widget.decoration?.labelText == '実勤務時間（休憩を除く）');
    await tester.ensureVisible(hours);
    await tester.enterText(hours, '7.25');
    await tester.ensureVisible(button);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
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
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
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
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(facts.confirmations, 1);
    expect(facts.savedHours, isNull);
    expect(reports.draftWrites, 0);
  });
}


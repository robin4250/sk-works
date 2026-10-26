// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
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
  bool omitSource = false, staleSupervisorRead = false, missingReport = false, peerClosed = false;
  String viewerActor = _actor, viewerWorker = _worker;
  bool recoveryChoices = false, documentMode = false;
  bool explicitMode = false, finalized = false, explicitOnSave = false;
  String? category;
  DailyReportCompanyAllowanceSelections? savedSelections;
  String savedAllowanceLabel = '';
  int savedAdjustment = 0;
  List<Map<String, Object?>>? savedWorkerPayload;
  String description = '保存済みの作業';
  bool get persistedSupervisor => supervisorSaved && !staleSupervisorRead;
  int draftWrites = 0, ordinaryReporterWrites = 0, anchorReads = 0;
  List<DailyReportWorkerDraft> get workers => [
    DailyReportWorkerDraft(workerId: _worker, workerName: '報告者', workCategory: category,
      allowanceLabel: savedAllowanceLabel, allowanceAmount: savedAdjustment,
      companyAllowanceSelections: savedSelections ?? (recoveryChoices ? DailyReportCompanyAllowanceSelections([]) : null),
      sourceClockInId: omitSource ? null : _source, sourceClockOutAt: DateTime(2026, 10, 25, 17)),
    if (peerOpen) DailyReportWorkerDraft(workerId: _peer, workerName: '勤務継続中',
      workCategory: category, companyAllowanceSelections: savedSelections ?? (recoveryChoices ? DailyReportCompanyAllowanceSelections([]) : null),
      sourceClockInId: '00000000-0000-0000-0000-000000000051',
      sourceClockOutAt: peerClosed ? DateTime(2026, 10, 25, 18) : null),
  ];
  @override String? get currentActorId => viewerActor;
  @override String? get notificationRetryUserId => null;
  @override Future<List<DailyReportSiteGroup>> loadClockedInGroups(DateTime date) async => [
    DailyReportSiteGroup(siteId: _site, siteName: '対象現場', workers: workers),
  ];
  @override Future<DailyReportRecord?> loadReport({required DateTime date,
    String? siteId, String? routeAssignmentId, String? vehicleClockInAnchorId,
    String? reportId}) async => missingReport ? null : DailyReportRecord(id: _report, companyId: _company,
      date: date, siteId: _site, siteName: '対象現場', workDescription: description,
      status: (explicitMode ? finalized : persistedSupervisor && !documentMode) ? 'signed' : 'draft', workers: workers,
      reporterSignerName: reporterSaved ? '最初の報告者' : null,
      reporterSignatureJson: reporterSaved ? {'strokes': [[{'x': 0.1, 'y': 0.2}]]} : null,
      responsibleSignerName: persistedSupervisor ? '責任者' : null,
      responsibleSignatureJson: persistedSupervisor ? {'strokes': [[{'x': 0.1, 'y': 0.2}]]} : null);
  @override Future<List<DailyReportEvidenceRecord>> loadAttendanceEvidence({String? reportId,
    required DateTime date, String? siteId, String? routeAssignmentId}) async => [];
  @override Future<List<DailyReportWorkerDraft>> loadAnchoredWorkers({required String anchorId,
    required DateTime workDate, required List<DailyReportWorkerDraft> existing,
    required List<DailyReportWorkerDraft> fallback, required bool allowNewMembers}) async { anchorReads++; return existing; }
  @override Future<bool> vehicleMeterEnabledForAnchor(String? anchor) async => false;
  @override Future<CompanyAllowanceLabelSnapshot> loadCompanyAllowanceLabels({
    required Iterable<String> workerIds, String? expectedCompanyId}) async =>
      const CompanyAllowanceLabelSnapshot(companyId: _company, version: 1, items: []);
  @override Future<Map<String, Set<String>>> loadCompanyAllowanceEligibility({
    required String reportId, required Iterable<String> workerIds, required CompanyAllowanceLabelSnapshot snapshot}) async =>
      {for (final workerId in workerIds) workerId: <String>{}};
  @override Future<bool> hasApprovedEdit(String reportId) async => false;
  @override Future<String> loadResponsibleName({String? siteId, String? routeAssignmentId}) async => '責任者';
  @override Future<String> saveDraft({String? reportId, String? siteId,
    String? routeAssignmentId, required DateTime date, required String workDescription,
    required List<DailyReportWorkerDraft> workers, String? groupClockInAnchorId,
    String? vehicleClockInAnchorId}) async {
    draftWrites++;
    if (explicitOnSave) explicitMode = true;
    description = workDescription; category = workers.first.workCategory;
    savedSelections = workers.first.companyAllowanceSelections;
    savedAllowanceLabel = workers.first.allowanceLabel; savedAdjustment = workers.first.allowanceAmount;
    savedWorkerPayload = [for (final worker in workers) worker.toRpcJson()];
    return _report;
  }
  @override Future<void> saveReporterSignature({required String reportId,
    required String signerName, required Object signatureJson}) async { ordinaryReporterWrites++; }
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Hours implements PaidWorkHoursRepository {
  bool required = false, fail = false, versionTwo = false;
  String actorId = _actor;
  final workersRead = <String>[];
  @override Future<PaidWorkHoursSnapshot> load({required String companyId,
    required String workerId, required String reportId}) async {
    workersRead.add(workerId);
    if (fail) throw StateError('hours API unavailable');
    return PaidWorkHoursSnapshot(actorId: actorId, companyId: companyId,
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
  int financialPreparations = 0, freshReporterWrites = 0;
  List<SharedWorkerFactsTransitionInput>? financialInputs;
  String? source = _source;
  bool managerNoOwnWorker = false;
  List<Map<String, dynamic>>? provisionalPayload;
  bool workOnly = true, ready = false, documentOnly = false;
  int documentEdits = 0, documentSaves = 0;
  int supervisorWrites = 0, finalizationWrites = 0, provisionalPreparations = 0;
  bool latePeerStage = false, loseStageAcknowledgement = false;
  int actualSourceBindings = 0;
  bool failFinalization = false, loseFinalizationAcknowledgement = false;
  SharedDailyReportContext get state => SharedDailyReportContext(actorId: reports.viewerActor,
    companyId: _company, workerId: managerNoOwnWorker ? null : reports.viewerWorker, reportId: _report, sourceClockInId: source,
    clockOutId: '00000000-0000-0000-0000-000000000060', workDate: _date,
    state: hold ? 'managed_financial_hold' : !enabled ? 'disabled' : reports.supervisorSaved ? 'supervisor_saved' :
      reports.reporterSaved ? 'reporter_saved_waiting_supervisor' : 'reporter_required',
    enabled: enabled, canManageAttendance: manager, reporterSaved: reports.reporterSaved,
    explicitFinalizationRequired: reports.explicitMode,
    explicitFinalizationReady: reports.explicitMode && reports.reporterSaved && reports.supervisorSaved && !reports.finalized,
    explicitFinalizationCompleted: reports.explicitMode && reports.finalized,
    supervisorSaved: reports.supervisorSaved, sourceAttached: source != null,
    reporterName: reports.reporterSaved ? '最初の報告者' : '',
    reportStatus: (reports.explicitMode ? reports.finalized : reports.supervisorSaved) ? 'signed' : 'draft',
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
      'work_description': reports.description},
      'roster': [for (final worker in reports.workers) {'worker_id': worker.workerId}]});
  @override Future<SharedDailyReportContext> loadForSource(String sourceClockInId) async => state;
  @override Future<SharedDailyReportContext> loadReport(String reportId, {String? expectedActor}) async => state;
  @override Future<SharedDailyReportContext> prepareProvisionalFacts({required SharedDailyReportContext before,
    required List<Map<String, dynamic>> workers}) async {
    expect(before.reporterSaved, reports.reporterSaved); expect(before.supervisorSaved, isFalse);
    provisionalPayload = workers;
    expect(workers.map((worker) => worker['worker_id']), reports.workers.map((worker) => worker.workerId));
    expect(workers.every((worker) => worker.containsKey('confirmed_hours')), isTrue);
    provisionalPreparations++;
    if (latePeerStage && reports.peerClosed && !ready) { ready = true; actualSourceBindings++; }
    if (loseStageAcknowledgement) { loseStageAcknowledgement = false; throw StateError('勤務実績の準備結果を受信できませんでした。'); }
    return state;
  }
  @override Future<SharedDailyReportContext> finalize({required SharedDailyReportContext before}) async {
    expect(before.canFinalize, isTrue);
    finalizationWrites++;
    if (failFinalization) throw StateError('給与・請求への反映に失敗しました。');
    reports.finalized = true;
    if (loseFinalizationAcknowledgement) throw StateError('確定結果を受信できませんでした。');
    return state;
  }
  @override Future<SharedDailyReportContext> collectSupervisor({required SharedDailyReportContext before,
    required String signerName, required Map<String, dynamic> signature}) async {
    expect(before.signatureScopeFingerprint, _scope);
    expect(signature['strokes'], isA<List>());
    supervisorWrites++;
    reports.supervisorSaved = true;
    if (prepared) prepared = false;
    return state;
  }
  @override Future<SharedDailyReportContext> submit({required SharedDailyReportContext before,
    required String workDescription, required List<Map<String, dynamic>> workers,
    required String signerName, required Map<String, dynamic> signature}) async {
    expect(before.financialTransitionValid, isTrue);
    expect(before.reporterSaved, isFalse); expect(signature['strokes'], isNotEmpty);
    freshReporterWrites++; reports.reporterSaved = true; ready = true;
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

  Future<void> revealFinalize(WidgetTester tester) async {
    final button = find.byKey(const ValueKey('daily-report-finalize'));
    await tester.scrollUntilVisible(button, 220, scrollable: find.byType(Scrollable).first, maxScrolls: 40);
    await tester.ensureVisible(button); await tester.pumpAndSettle();
  }
  for (final peerClosed in [false, true]) {
    testWidgets('another member stage prepares only an actually closed late peer before supervisor capture: $peerClosed', (tester) async {
      final reports = _Reports()..reporterSaved = true..explicitMode = true..peerOpen = true
        ..category = 'day'..recoveryChoices = true..viewerActor = '00000000-0000-0000-0000-000000000099'..viewerWorker = _peer;
      final shared = _Shared(reports)..latePeerStage = true..source = '00000000-0000-0000-0000-000000000051';
      final hours = _Hours()..actorId = reports.viewerActor;
      await open(tester, reports, hours, shared);
      reports.peerClosed = peerClosed;
      await reveal(tester, '責任者サイン'); await tester.tap(find.text('責任者サイン')); await tester.pumpAndSettle();
      expect(shared.provisionalPreparations, 1);
      expect(shared.actualSourceBindings, peerClosed ? 1 : 0);
      expect(reports.peerClosed, peerClosed); expect(shared.supervisorWrites, 0);
      if (peerClosed) {
        await tester.tap(find.text('この内容で責任者サインへ')); await tester.pumpAndSettle();
        expect(find.byType(SignatureCapturePage), findsOneWidget);
      } else {
        expect(find.byType(SignatureCapturePage), findsNothing);
        expect(find.text('責任者サインの前に確認が必要です'), findsOneWidget);
      }
    });
  }
  testWidgets('lost preparation ACK refreshes before retry and never fabricates another source', (tester) async {
    final reports = _Reports()..reporterSaved = true..explicitMode = true..peerOpen = true..category = 'day'..recoveryChoices = true;
    final shared = _Shared(reports)..latePeerStage = true..loseStageAcknowledgement = true;
    await open(tester, reports, _Hours(), shared); reports.peerClosed = true;
    await reveal(tester, '責任者サイン'); await tester.tap(find.text('責任者サイン')); await tester.pumpAndSettle();
    expect(shared.provisionalPreparations, 1); expect(shared.actualSourceBindings, 1);
    expect(find.byType(SignatureCapturePage), findsNothing);
    await tester.tap(find.text('責任者サイン')); await tester.pumpAndSettle();
    expect(shared.provisionalPreparations, 2); expect(shared.actualSourceBindings, 1);
    await tester.tap(find.text('この内容で責任者サインへ')); await tester.pumpAndSettle();
    expect(find.byType(SignatureCapturePage), findsOneWidget); expect(shared.supervisorWrites, 0);
  });

  Future<void> expandMemberFields(WidgetTester tester) async {
    final member = find.descendant(of: find.byType(ExpansionTile), matching: find.text('報告者'));
    await tester.scrollUntilVisible(member, 180, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(member); await tester.pumpAndSettle();
    await tester.tap(member); await tester.pumpAndSettle();
  }
  Future<void> enterOptionalTime(WidgetTester tester, String label, String value) async {
    final field = find.byWidgetPredicate((widget) => widget is TextField && widget.decoration?.labelText == label);
    await tester.scrollUntilVisible(field, 180, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(field); await tester.pumpAndSettle();
    await tester.enterText(field, value); FocusManager.instance.primaryFocus?.unfocus(); await tester.pumpAndSettle();
  }
  for (final example in [
    ('残業(h)', 'abc', '報告者サイン', '残業時間'),
    ('早出(h)', 'NaN', '手当を選ぶ', '早出時間'),
    ('夜間(h)', '-1', '入力途中を保存', '夜間時間'),
    ('残業(h)', '25', '報告者サイン', '残業時間'),
    ('早出(h)', '24.0001', '手当を選ぶ', '早出時間'),
    ('夜間(h)', 'Infinity', '入力途中を保存', '夜間時間'),
  ]) {
    testWidgets('nonempty invalid optional time is never saved as zero: $example', (tester) async {
      final reports = _Reports();
      if (example.$3 == '手当を選ぶ') {
        reports.missingReport = true;
        await tester.pumpWidget(MaterialApp(home: DailyReportPage(initialDate: _date, initialSiteId: _site,
          vehicleClockInId: _source, repositoryForTesting: reports, paidHoursRepositoryForTesting: _Hours(),
          sharedReportRepositoryForTesting: _MissingShared(reports, 'report_missing'))));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const ValueKey('daily-report-work-description')), '実際の作業');
        FocusManager.instance.primaryFocus?.unfocus(); await tester.pumpAndSettle();
      } else {
        await open(tester, reports, _Hours(), _Shared(reports));
      }
      await expandMemberFields(tester); await enterOptionalTime(tester, example.$1, example.$2);
      await reveal(tester, example.$3); await tester.tap(find.text(example.$3)); await tester.pumpAndSettle();
      expect(reports.draftWrites, 0); expect(reports.savedWorkerPayload, isNull);
      expect(find.byType(SignatureCapturePage), findsNothing);
      expect(find.textContaining('${example.$4}を0〜24'), findsOneWidget);
    });
  }
  testWidgets('blank optional times save explicit zero without financial finalization', (tester) async {
    final reports = _Reports(); await open(tester, reports, _Hours(), _Shared(reports));
    await expandMemberFields(tester);
    for (final label in ['残業(h)', '早出(h)', '夜間(h)']) { await enterOptionalTime(tester, label, ''); }
    await reveal(tester, '入力途中を保存'); await tester.tap(find.text('入力途中を保存')); await tester.pumpAndSettle();
    expect(reports.draftWrites, 1);
    for (final key in ['overtime_hours', 'early_hours', 'night_hours']) { expect(reports.savedWorkerPayload!.single[key], 0); }
    expect(reports.reporterSaved, isFalse); expect(reports.finalized, isFalse);
  });
  testWidgets('reporter review explicitly confirms no registered selection while preserving legacy text and amount', (tester) async {
    final reports = _Reports()..explicitMode = true..category = 'day'
      ..savedAllowanceLabel = '旧手入力の手当'..savedAdjustment = 5000;
    await open(tester, reports, _Hours(), _Shared(reports));
    await reveal(tester, '報告者サイン'); await tester.tap(find.text('報告者サイン')); await tester.pumpAndSettle();
    final capture = tester.widget<SignatureCapturePage>(find.byType(SignatureCapturePage));
    expect(capture.reviewText, contains('登録手当：選択なし'));
    expect(capture.reviewText, contains('旧手入力の手当'));
    expect(reports.savedWorkerPayload!.single['company_allowance_selections'], {'contract_version': 1, 'items': []});
    expect(reports.savedWorkerPayload!.single['allowance_label'], '旧手入力の手当');
    expect(reports.savedWorkerPayload!.single['allowance_amount'], 5000);
    expect(reports.reporterSaved, isFalse); expect(reports.finalized, isFalse);
  });

  testWidgets('saved-report manager without own source stages entered hours before reporter capture', (tester) async {
    final reports = _Reports()..explicitMode = true..category = 'day'..recoveryChoices = true;
    final shared = _Shared(reports)..manager = true..managerNoOwnWorker = true..source = null;
    await open(tester, reports, _Hours(), shared);
    final field = find.byKey(const ValueKey('daily-report-confirmed-hours/$_worker'));
    await tester.scrollUntilVisible(field, 160, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(field); await tester.pumpAndSettle();
    await tester.enterText(field, '7.25'); FocusManager.instance.primaryFocus?.unfocus(); await tester.pumpAndSettle();
    await reveal(tester, '報告者サイン'); await tester.tap(find.text('報告者サイン')); await tester.pumpAndSettle();
    expect(shared.provisionalPreparations, 1);
    expect(shared.provisionalPayload!.single['confirmed_hours'], 7.25);
    expect(shared.provisionalPayload!.single['company_allowance_selections'], {'contract_version': 1, 'items': []});
    expect(find.byType(SignatureCapturePage), findsOneWidget);
    expect(tester.widget<SignatureCapturePage>(find.byType(SignatureCapturePage)).reviewText, contains('7.25時間'));
    expect(reports.reporterSaved, isFalse); expect(shared.supervisorWrites, 0);
  });

  testWidgets('actual signatures remain draft until explicit step five succeeds', (tester) async {
    final reports = _Reports()..reporterSaved = true..supervisorSaved = true..explicitMode = true;
    final shared = _Shared(reports)..ready = true;
    await open(tester, reports, _Hours(), shared);
    await revealFinalize(tester);
    expect(reports.finalized, isFalse); expect(shared.finalizationWrites, 0);
    await tester.tap(find.byKey(const ValueKey('daily-report-finalize')));
    await tester.pumpAndSettle();
    expect(reports.finalized, isTrue); expect(shared.finalizationWrites, 1);
    expect(find.text('確定済み'), findsOneWidget);
  });
  testWidgets('missing supervisor cannot unlock step five', (tester) async {
    final reports = _Reports()..reporterSaved = true..explicitMode = true;
    final shared = _Shared(reports);
    await open(tester, reports, _Hours(), shared);
    await revealFinalize(tester);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('daily-report-finalize'))).onPressed, isNull);
    expect(shared.finalizationWrites, 0);
  });
  testWidgets('failed finalization does not report success or lose retry', (tester) async {
    final reports = _Reports()..reporterSaved = true..supervisorSaved = true..explicitMode = true;
    final shared = _Shared(reports)..failFinalization = true;
    await open(tester, reports, _Hours(), shared); await revealFinalize(tester);
    await tester.tap(find.byKey(const ValueKey('daily-report-finalize'))); await tester.pumpAndSettle();
    expect(reports.finalized, isFalse); expect(find.text('確定済み'), findsNothing);
    expect(shared.finalizationWrites, 1);
    shared.failFinalization = false; await revealFinalize(tester);
    await tester.tap(find.byKey(const ValueKey('daily-report-finalize'))); await tester.pumpAndSettle();
    expect(shared.finalizationWrites, 2); expect(reports.finalized, isTrue);
  });
  testWidgets('lost committed finalization acknowledgement reloads without a second write', (tester) async {
    final reports = _Reports()..reporterSaved = true..supervisorSaved = true..explicitMode = true;
    final shared = _Shared(reports)..loseFinalizationAcknowledgement = true;
    await open(tester, reports, _Hours(), shared); await revealFinalize(tester);
    await tester.tap(find.byKey(const ValueKey('daily-report-finalize'))); await tester.pumpAndSettle();
    expect(shared.finalizationWrites, 1); expect(reports.finalized, isTrue);
    expect(find.byKey(const ValueKey('daily-report-finalize')), findsNothing);
  });

  test('financial and visit failures provide actionable Japanese without SQL details', () {
    const examples = {
      'explicit_report_finalized_payroll_protected': '対象月の給与が確定済み',
      'explicit_report_finalized_invoice_protected': '対象月の請求書が確定済み',
      'explicit_report_payroll_projection_blocked': '給与計算に必要な設定',
      'explicit_report_invoice_projection_missing': '請求先と請求設定',
      'explicit_report_actual_facts_required': '実勤務時間',
      'explicit_report_confirmation_reason_invalid': '1〜1000文字',
      'shared_report_scope_changed': '再読み込み',
      'explicit_route_finalization_not_allowed': '現場メンバー',
    };
    for (final entry in examples.entries) {
      final message = dailyReportActionErrorMessage(PostgrestException(message: entry.key,
        code: 'P0001', details: 'private.internal_table: synthetic SQL details'));
      expect(message, contains(entry.value));
      expect(message, isNot(contains('通信状態')));
      expect(message, isNot(contains(entry.key)));
      expect(message, isNot(contains('private.internal_table')));
    }
  });

  testWidgets('first saved draft enrollment rechecks missing work category before capturing reporter', (tester) async {
    final reports = _Reports()..explicitOnSave = true;
    final shared = _Shared(reports);
    await open(tester, reports, _Hours(), shared);
    await tester.enterText(find.byKey(const ValueKey('daily-report-work-description')), '更新した実際の作業');
    FocusManager.instance.primaryFocus?.unfocus(); await tester.pumpAndSettle();
    await reveal(tester, '報告者サイン');
    await tester.tap(find.text('報告者サイン')); await tester.pumpAndSettle();
    expect(reports.explicitMode, isTrue); expect(reports.draftWrites, 1);
    expect(find.byType(SignatureCapturePage), findsNothing);
    expect(find.textContaining('②の勤務区分'), findsOneWidget,
      reason: tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).join(' | '));
    expect(reports.reporterSaved, isFalse); expect(shared.freshReporterWrites, 0);
  });

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
    final category = find.byWidgetPredicate((widget) =>
      widget is DropdownButtonFormField<String> && widget.key.toString().contains('facts-category/'));
    await tester.scrollUntilVisible(category, -200, scrollable: find.byType(Scrollable).first);
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
    Navigator.of(tester.element(find.byType(SignatureCapturePage))).pop(
      const SignatureResult(signerName: '新たな報告者', strokes: [[Offset(0.2, 0.3)]]));
    await tester.pumpAndSettle();
    expect(shared.freshReporterWrites, 1); expect(reports.reporterSaved, isTrue);
    expect(reports.supervisorSaved, isFalse); expect(reports.draftWrites, 0);
    await reveal(tester, '責任者サイン'); await tester.tap(find.text('責任者サイン'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('この内容で責任者サインへ')); await tester.pumpAndSettle();
    expect(find.byType(SignatureCapturePage), findsOneWidget);
    Navigator.of(tester.element(find.byType(SignatureCapturePage))).pop(
      const SignatureResult(signerName: '新たな現場責任者', strokes: [[Offset(0.3, 0.4)]]));
    await tester.pumpAndSettle();
    expect(shared.supervisorWrites, 1); expect(reports.supervisorSaved, isTrue);
    expect(shared.prepared, isFalse); expect(shared.financialPreparations, 1);
    expect(reports.draftWrites, 0); expect(shared.documentSaves, 0);
  });
  for (final valid in [false, true]) {
    for (final sourceAnchor in [false, true]) {
    testWidgets('reopened staged report avoids old draft writer, valid=$valid, source=$sourceAnchor', (tester) async {
      final reports = _Reports();
      final shared = _Shared(reports)..prepared = true..preparedValid = valid;
      if (sourceAnchor) {
        await tester.pumpWidget(MaterialApp(home: DailyReportPage(initialDate: _date,
          initialSiteId: _site, initialReportId: _report, groupClockInAnchorId: _source,
          repositoryForTesting: reports, paidHoursRepositoryForTesting: _Hours()..versionTwo = true,
          sharedReportRepositoryForTesting: shared, workerFactsRepositoryForTesting: _Facts())));
        await tester.pumpAndSettle();
      } else {
        await open(tester, reports, _Hours()..versionTwo = true, shared, facts: _Facts());
      }
      expect(reports.anchorReads, 0);
      await reveal(tester, '報告者サイン'); await tester.tap(find.text('報告者サイン').first);
      await tester.pumpAndSettle();
      expect(reports.draftWrites, 0); expect(shared.documentSaves, 0);
      expect(find.byType(SignatureCapturePage), valid ? findsOneWidget : findsNothing);
    });
    }
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
    final category = find.byWidgetPredicate((widget) =>
      widget is DropdownButtonFormField<String> && widget.key.toString().contains('facts-category/'));
    await tester.scrollUntilVisible(category, -200, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(category);
    await tester.pumpAndSettle();
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
    await tester.scrollUntilVisible(description, -200, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(description);
    await tester.enterText(description, '手直しした作業内容');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await reveal(tester, '入力途中を保存');
    await tester.tap(find.text('入力途中を保存'));
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
    await tester.scrollUntilVisible(description, -200, scrollable: find.byType(Scrollable).first);
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
    expect(find.text('入力途中を保存'), findsNothing);
    expect(reports.draftWrites, 0);
    expect(reports.ordinaryReporterWrites, 0);
  });
  testWidgets('financial hold blocks draft and signature edits without retrying writes', (tester) async {
    final reports = _Reports();
    await open(tester, reports, _Hours(), _Shared(reports)..hold = true);
    expect(find.textContaining('手入力済み勤怠・給与との差異'), findsOneWidget);
    expect(find.text('入力途中を保存'), findsNothing);
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



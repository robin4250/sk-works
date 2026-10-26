import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import 'shared_worker_facts_repository.dart';

class SharedReportManagementHold implements Exception {
  const SharedReportManagementHold({this.reasonCode = 'managed_attendance_financial_vector_changed_pending'});
  final String reasonCode;
  static const reasons = {'managed_attendance_financial_vector_changed_pending',
    'managed_roster_manual_worker_scope_mismatch', 'managed_roster_existing_projection_pending',
    'managed_roster_manual_source_ambiguous'};
  String get message => reasonCode == 'managed_attendance_financial_vector_changed_pending'
      ? '手入力済み勤怠・給与との差異があるため、サインの保存を保留しています。勤怠管理で確認してください。'
      : '手入力された勤務原本の対象・重複・既存日報との関連を勤怠管理で確認してください。';
  bool get retryAllowed => false;
  @override
  String toString() => message;
}

class SharedDailyReportContext {
  const SharedDailyReportContext({
    required this.actorId, required this.companyId, required this.workDate,
    required this.state, required this.enabled, required this.canManageAttendance,
    required this.reporterSaved, required this.supervisorSaved,
    required this.sourceAttached, this.workerId, this.reportId,
    this.sourceClockInId, this.clockOutId, this.expectedUpdatedAt,
    this.reporterName = '', this.reportStatus, this.signatureScopeFingerprint,
    this.hoursAnnex, this.workBasis, this.supervisorReady = false,
    this.firstReporterCoversWorkOnly = false,
    this.documentOnly = false, this.documentComplete = false,
    this.documentEditable = false, this.financialConfirmationRequired = false,
    this.documentBasis, this.financialResigningSupported = false,
    this.financialTransitionId, this.financialTransitionValid = false,
    this.managementHoldReason, this.approvedEditRequestId,
    this.explicitFinalizationRequired = false, this.explicitFinalizationReady = false,
    this.explicitFinalizationCompleted = false, this.explicitFinalizationEditable = false,
    this.pendingWorkerIds = const [], this.supervisorPendingReasons = const [],
  });
  final String actorId, companyId, state, reporterName;
  final String? workerId, reportId, sourceClockInId, clockOutId, reportStatus;
  final DateTime workDate;
  final DateTime? expectedUpdatedAt;
  final String? signatureScopeFingerprint;
  final Map<String, dynamic>? hoursAnnex;
  final Map<String, dynamic>? workBasis;
  final Map<String, dynamic>? documentBasis;
  final bool supervisorReady;
  final bool explicitFinalizationRequired, explicitFinalizationReady, explicitFinalizationCompleted, explicitFinalizationEditable;
  bool get canFinalize => enabled && explicitFinalizationRequired && explicitFinalizationReady &&
      !explicitFinalizationCompleted && reporterSaved && supervisorSaved &&
      reportId != null && expectedUpdatedAt != null && signatureScopeFingerprint != null;
  final bool firstReporterCoversWorkOnly;
  final bool documentOnly, documentComplete, documentEditable, financialConfirmationRequired;
  final bool financialResigningSupported, financialTransitionValid;
  final int? financialTransitionId;
  bool get financialTransitionPending => financialTransitionId != null;
  final String? managementHoldReason;
  final String? approvedEditRequestId;
  bool get isManagementHold => state == 'managed_financial_hold';
  String get managementHoldMessage => SharedReportManagementHold(
      reasonCode: managementHoldReason ?? 'managed_attendance_financial_vector_changed_pending').message;
  final List<String> pendingWorkerIds, supervisorPendingReasons;
  final bool enabled, canManageAttendance, reporterSaved, supervisorSaved,
      sourceAttached;
  bool get signedFactsReadOnly => reporterSaved || supervisorSaved;
  bool get canAccessSupervisorCollection => enabled && !supervisorSaved &&
      (canManageAttendance || approvedEditRequestId != null || (reporterSaved && sourceClockInId != null));
  bool get canCollectSupervisor => canAccessSupervisorCollection && supervisorReady &&
      signatureScopeFingerprint != null &&
      (documentOnly || !(hoursAnnex?['required'] == true &&
          (hoursAnnex?['enabled'] != true || hoursAnnex?['ready'] != true)));
  bool get hoursAnnexRequired => hoursAnnex?['required'] == true;
  bool get hoursAnnexReady => hoursAnnex?['enabled'] == true && hoursAnnex?['ready'] == true;
  String get workDescription => (workBasis?['report'] as Map?)?['work_description'] as String? ?? '';
  List<String> get workRosterIds => workBasis == null ? const [] :
      List<String>.unmodifiable((workBasis!['roster'] as List).map((e) => (e as Map)['worker_id'] as String));
  List<Map<String, dynamic>> get hoursAnnexInputs => hoursAnnex == null
      ? const [] : List<Map<String, dynamic>>.unmodifiable(
          (hoursAnnex!['inputs'] as List).map((e) => Map<String, dynamic>.unmodifiable(Map<String, dynamic>.from(e as Map))));
  bool get needsApprovedEdit => state == 'recorded_hours_basis_requires_approved_edit';

  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );
  static const _states = {
    'disabled', 'own_checkout_required', 'source_conflict', 'report_missing',
    'roster_membership_required', 'reporter_required',
    'reporter_saved_waiting_supervisor', 'supervisor_saved',
    'recorded_hours_basis_requires_approved_edit',
    'managed_financial_hold',
  };
  factory SharedDailyReportContext.parse(Object? raw, {
    required String actorId, String? sourceClockInId, String? reportId,
    String? companyId, String? workerId, DateTime? workDate,
  }) {
    Never invalid() => throw StateError('共同日報の状態を確認できません。再読込してください。');
    if (raw is! Map || raw['schema'] != 1 || raw['actor_id'] != actorId ||
        !_uuid.hasMatch(actorId)) { invalid(); }
    final row = Map<String, dynamic>.from(raw);
    String? id(String key, {bool mustExist = false}) {
      final value = row[key];
      if (value == null && !mustExist) { return null; }
      if (value is! String || !_uuid.hasMatch(value)) { invalid(); }
      return value;
    }
    final company = id('company_id', mustExist: true)!;
    final worker = id('worker_id');
    final source = id('source_clock_in_id');
    final report = id('report_id');
    final out = id('clock_out_id');
    if ((companyId != null && company != companyId) ||
        (workerId != null && worker != workerId) ||
        (sourceClockInId != null && source != sourceClockInId) ||
        (reportId != null && report != reportId)) { invalid(); }
    final dayRaw = row['work_date'];
    if (dayRaw is! String || !RegExp(r'^20\d{2}-\d{2}-\d{2}$').hasMatch(dayRaw)) { invalid(); }
    final day = DateTime.tryParse(dayRaw);
    if (day == null || day.toIso8601String().substring(0, 10) != dayRaw ||
        (workDate != null && DateTime(workDate.year, workDate.month, workDate.day) != day)) { invalid(); }
    for (final key in ['enabled', 'can_manage_attendance', 'reporter_saved', 'supervisor_saved', 'source_attached', 'supervisor_ready', 'first_reporter_covers_work_only', 'management_hold']) {
      if (row[key] is! bool) { invalid(); }
    }
    for (final key in ['document_only', 'document_complete', 'document_editable', 'financial_confirmation_required', 'financial_resigning_supported', 'financial_transition_valid', 'new_actual_reporter_and_supervisor_signatures_required']) {
      if (row.containsKey(key) && row[key] is! bool) { invalid(); }
    }
    const finalizationKeys = ['explicit_finalization_required', 'explicit_finalization_ready', 'explicit_finalization_completed'];
    if (finalizationKeys.any(row.containsKey)) {
      if (finalizationKeys.any((key) => row[key] is! bool)) { invalid(); }
      if (row['explicit_finalization_required'] != true &&
          (row['explicit_finalization_ready'] == true || row['explicit_finalization_completed'] == true) ||
          row['explicit_finalization_required'] == true && row['enabled'] != true ||
          row['explicit_finalization_ready'] == true &&
            (row['reporter_saved'] != true || row['supervisor_saved'] != true || row['report_status'] != 'draft') ||
          row['explicit_finalization_completed'] == true &&
            (row['reporter_saved'] != true || row['supervisor_saved'] != true || row['report_status'] != 'signed' ||
             row['explicit_finalization_ready'] == true)) { invalid(); }
    }
    if (row.containsKey('explicit_finalization_editable') &&
        (row['explicit_finalization_editable'] is! bool ||
          row['explicit_finalization_editable'] == true &&
            (row['explicit_finalization_required'] != true || row['report_status'] != 'draft' ||
             row['explicit_finalization_completed'] == true))) { invalid(); }
    final transitionId = row['financial_transition_id'];
    if (transitionId != null && (transitionId is! int || transitionId <= 0 ||
        row['financial_transition_state'] != 'ready_for_real_signatures' ||
        row['financial_transition_valid'] is! bool ||
        row['new_actual_reporter_and_supervisor_signatures_required'] != true ||
        row['report_status'] != 'draft' || row['document_only'] == true) ||
        transitionId == null && (row.containsKey('financial_transition_state') ||
          row.containsKey('financial_transition_valid') ||
          row.containsKey('new_actual_reporter_and_supervisor_signatures_required'))) { invalid(); }
    final documentOnly = row['document_only'] == true;
    final documentComplete = row['document_complete'] == true;
    final documentEditable = row['document_editable'] == true;
    final financialConfirmationRequired = row['financial_confirmation_required'] == true;
    if (documentOnly && (row['enabled'] != true || row['first_reporter_covers_work_only'] != true ||
        row['hours_annex'] != null || !financialConfirmationRequired) ||
        !documentOnly && (documentComplete || documentEditable || financialConfirmationRequired) ||
        documentComplete && (row['reporter_saved'] != true || row['supervisor_saved'] != true) ||
        documentEditable && (row['report_status'] != 'draft' || row['reporter_saved'] != true)) { invalid(); }
    final state = row['state'];
    if (state is! String || !_states.contains(state) ||
        (state == 'disabled') != (row['enabled'] == false)) { invalid(); }
    if ((row['reporter_saved'] == true || row['supervisor_saved'] == true) && report == null) { invalid(); }
    final stamp = row['report_updated_at'];
    final updatedAt = stamp is String ? DateTime.tryParse(stamp) : null;
    if (stamp != null && updatedAt == null) { invalid(); }
    final fingerprint = row['signature_scope_fingerprint'];
    if (fingerprint != null && (fingerprint is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(fingerprint))) { invalid(); }
    if (const ['reporter_required', 'reporter_saved_waiting_supervisor', 'supervisor_saved'].contains(state) &&
        (updatedAt == null || fingerprint == null)) { invalid(); }
    Object? freeze(Object? value) {
      if (value is Map) { return Map<String, dynamic>.unmodifiable(value.map((k, v) => MapEntry(k as String, freeze(v)))); }
      if (value is List) { return List<dynamic>.unmodifiable(value.map(freeze)); }
      return value;
    }
    final work = row['work_basis'];
    Map<String, dynamic>? workBasis;
    if (fingerprint != null || work != null) {
      if (work is! Map || work['contract_version'] != 2 || work['report'] is! Map || work['roster'] is! List) { invalid(); }
      final header = work['report'] as Map;
      if (header['id'] != report || header['company_id'] != company || header['work_date'] != dayRaw ||
          (header['work_description'] != null && header['work_description'] is! String)) { invalid(); }
      for (final key in ['site_id', 'route_assignment_id']) {
        if (header[key] != null && (header[key] is! String || !_uuid.hasMatch(header[key] as String))) { invalid(); }
      }
      if ((header['site_id'] == null) == (header['route_assignment_id'] == null)) { invalid(); }
      final roster = work['roster'] as List;
      if (roster.isEmpty || roster.length > 100 || roster.any((e) => e is! Map || e['worker_id'] is! String || !_uuid.hasMatch(e['worker_id'] as String))) { invalid(); }
      if (roster.map((e) => (e as Map)['worker_id']).toSet().length != roster.length) { invalid(); }
      workBasis = freeze(work) as Map<String, dynamic>;
    }
    Map<String, dynamic>? documentBasis;
    if (documentOnly) {
      final basis = row['document_basis'];
      if (basis is! Map || basis['report'] is! Map || basis['workers'] is! List) { invalid(); }
      final header = basis['report'] as Map;
      final workers = basis['workers'] as List;
      if (header['id'] != report || header['company_id'] != company || header['report_date'] != dayRaw ||
          header['work_description'] != (workBasis?['report'] as Map?)?['work_description'] ||
          workers.length != (workBasis?['roster'] as List?)?.length ||
          workers.any((w) => w is! Map || w['report_id'] != report || w['worker_id'] is! String ||
            !_uuid.hasMatch(w['worker_id'] as String)) ||
          workers.map((w) => (w as Map)['worker_id']).toSet().length != workers.length ||
          workers.any((w) => !(workBasis!['roster'] as List).any((r) => (r as Map)['worker_id'] == (w as Map)['worker_id']))) { invalid(); }
      documentBasis = freeze(basis) as Map<String, dynamic>;
    }
    final annex = row['hours_annex'];
    Map<String, dynamic>? hoursAnnex;
    if (annex != null) {
      if (annex is! Map || annex['schema'] != 2 ||
          annex['enabled'] is! bool || annex['required'] is! bool || annex['ready'] is! bool ||
          annex['fingerprint'] is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(annex['fingerprint'] as String) ||
          annex['inputs'] is! List) { invalid(); }
      final inputs = annex['inputs'] as List;
      if (inputs.length > 100) { invalid(); }
      final inputWorkers = <String>{};
      for (final value in inputs) {
        if (value is! Map || value['worker_id'] is! String || !_uuid.hasMatch(value['worker_id'] as String) ||
            !inputWorkers.add(value['worker_id'] as String) || value['work_date'] != dayRaw ||
            value['revision'] is! int || (value['revision'] as int) < 0 ||
            value['source_fingerprint'] is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(value['source_fingerprint'] as String)) { invalid(); }
        for (final key in ['hours_required', 'source_current', 'required', 'confirmed', 'facts_confirmed', 'facts_current']) {
          if (value[key] is! bool) { invalid(); }
        }
        final hours = value['hours'];
        if (hours != null && (hours is! num || !hours.isFinite || hours < 0 || hours > 24)) { invalid(); }
        if (value['confirmed'] == true && value['hours_required'] == true && hours == null) { invalid(); }
        if (value['confirmation_id'] != null && (value['confirmation_id'] is! int || (value['confirmation_id'] as int) < 1)) { invalid(); }
        if (value['confirmed_by'] != null && (value['confirmed_by'] is! String || !_uuid.hasMatch(value['confirmed_by'] as String))) { invalid(); }
        if (value['confirmed_at'] != null && (value['confirmed_at'] is! String || DateTime.tryParse(value['confirmed_at'] as String) == null)) { invalid(); }
        final facts = value['worker_facts'];
        if (facts != null) {
          const keys = {'schema', 'overtime_hours', 'early_hours', 'night_hours', 'work_category',
            'allowance_amount', 'allowance_label', 'company_allowance_selections',
            'company_allowance_legacy_labels', 'vehicle_id', 'route_assignment_id', 'odometer_km'};
          if (facts is! Map || facts.length != keys.length || !facts.keys.toSet().containsAll(keys) || facts['schema'] != 1) { invalid(); }
          bool finiteNumber(Object? v, num maximum) => v is num && v.isFinite && v >= 0 && v <= maximum &&
              ((v * 10000) - (v * 10000).round()).abs() < 0.000001;
          for (final key in ['overtime_hours', 'early_hours', 'night_hours']) {
            if (!finiteNumber(facts[key], 24)) { invalid(); }
          }
          if (!const ['day', 'night', 'holiday', 'holiday_night'].contains(facts['work_category']) ||
              facts['allowance_amount'] is! int || (facts['allowance_amount'] as int) < 0 ||
              (facts['allowance_amount'] as int) > 2147483647) { invalid(); }
          for (final key in ['allowance_label', 'company_allowance_legacy_labels']) {
            if (facts[key] != null && (facts[key] is! String || (facts[key] as String).length > 1048576)) { invalid(); }
          }
          for (final key in ['vehicle_id', 'route_assignment_id']) {
            if (facts[key] != null && (facts[key] is! String || !_uuid.hasMatch(facts[key] as String))) { invalid(); }
          }
          if (facts['vehicle_id'] == null ? facts['odometer_km'] != null : !finiteNumber(facts['odometer_km'], 999999999)) { invalid(); }
          final choices = facts['company_allowance_selections'];
          if (choices is! Map || choices['contract_version'] != 1 || choices['items'] is! List ||
              (choices['items'] as List).length > 2000) { invalid(); }
          final seenChoices = <String>{};
          for (final choice in choices['items'] as List) {
            if (choice is! Map || choice['id'] is! String || !_uuid.hasMatch(choice['id'] as String) ||
                !const ['company_legacy', 'company_common'].contains(choice['origin']) ||
                choice['registration_version'] is! int || (choice['registration_version'] as int) < 0 ||
                choice['name_snapshot'] is! String || !const ['hour', 'day', 'month'].contains(choice['unit']) ||
                (choice['generation'] != null && (choice['generation'] is! int || (choice['generation'] as int) < 1)) ||
                !seenChoices.add('${choice['origin']}:${choice['id']}')) { invalid(); }
          }
        }
        if (value['confirmed'] == true && (value['facts_current'] != true || value['source_current'] != true ||
            value['confirmation_id'] == null || value['confirmed_by'] == null || value['confirmed_at'] == null || value['worker_facts'] == null)) { invalid(); }
        if (value['reason'] is! List || (value['reason'] as List).any((e) => e is! String || e.length > 100)) { invalid(); }
        if (workBasis != null && !((workBasis['roster'] as List).any((e) => (e as Map)['worker_id'] == value['worker_id']))) { invalid(); }
      }
      if (annex['enabled'] == true && workBasis != null &&
          inputWorkers.length != (workBasis['roster'] as List).length) { invalid(); }
      if (annex['ready'] == true && inputs.any((e) => (e as Map)['confirmed'] != true)) { invalid(); }
      hoursAnnex = freeze(annex) as Map<String, dynamic>;
    }
    if (row['source_attached'] == true && (source == null || report == null)) { invalid(); }
    final pending = row['pending_members'];
    final reasons = row['supervisor_pending_reasons'];
    if (pending is! List || pending.length > 100 || reasons is! List ||
        reasons.any((e) => e is! String || e.length > 100) || reasons.length > 20) { invalid(); }
    final pendingIds = <String>[];
    for (final value in pending) {
      if (value is! Map || value['worker_id'] is! String || !_uuid.hasMatch(value['worker_id'] as String) ||
          value['reason'] is! String || !const ['clock_in_missing', 'clock_out_missing_or_conflicting'].contains(value['reason'])) { invalid(); }
      pendingIds.add(value['worker_id'] as String);
    }
    if (row['supervisor_ready'] == true && (pendingIds.isNotEmpty || reasons.isNotEmpty)) { invalid(); }
    if ((row['management_hold'] == true) != (state == 'managed_financial_hold') ||
        (row['management_hold'] == false && row['management_hold_reason'] != null) ||
        (state == 'managed_financial_hold' && (!SharedReportManagementHold.reasons.contains(row['management_hold_reason']) || row['supervisor_ready'] != false))) { invalid(); }
    return SharedDailyReportContext(
      actorId: actorId, companyId: company, workerId: worker, reportId: report,
      sourceClockInId: source, clockOutId: out, workDate: day, state: state,
      expectedUpdatedAt: updatedAt, enabled: row['enabled'] as bool,
      canManageAttendance: row['can_manage_attendance'] as bool,
      reporterSaved: row['reporter_saved'] as bool,
      supervisorSaved: row['supervisor_saved'] as bool,
      sourceAttached: row['source_attached'] as bool,
      reporterName: row['reporter_name'] is String ? row['reporter_name'] as String : '',
      reportStatus: row['report_status'] as String?,
      signatureScopeFingerprint: fingerprint as String?, hoursAnnex: hoursAnnex,
      workBasis: workBasis, documentBasis: documentBasis,
      firstReporterCoversWorkOnly: row['first_reporter_covers_work_only'] as bool,
      explicitFinalizationRequired: row['explicit_finalization_required'] == true,
      explicitFinalizationReady: row['explicit_finalization_ready'] == true,
      explicitFinalizationCompleted: row['explicit_finalization_completed'] == true,
      explicitFinalizationEditable: row['explicit_finalization_editable'] == true,
      financialResigningSupported: row['financial_resigning_supported'] == true,
      financialTransitionId: transitionId as int?, financialTransitionValid: row['financial_transition_valid'] == true,
      documentOnly: documentOnly, documentComplete: documentComplete,
      documentEditable: documentEditable, financialConfirmationRequired: financialConfirmationRequired,
      managementHoldReason: row['management_hold_reason'] as String?, approvedEditRequestId: id('approved_edit_request_id'),
      supervisorReady: row['supervisor_ready'] as bool,
      pendingWorkerIds: List<String>.unmodifiable(pendingIds),
      supervisorPendingReasons: List<String>.unmodifiable(reasons.cast<String>()),
    );
  }
}

class SharedDailyReportRepository {
  SharedDailyReportRepository(this._client);
  final SupabaseClient _client;
  static SharedDailyReportRepository? maybeCreate() =>
      !SupabaseBackend.isInitialized || SupabaseBackend.client.auth.currentUser == null
          ? null : SharedDailyReportRepository(SupabaseBackend.client);

  Future<Object?> _rpc(String name, Map<String, dynamic> parameters, {String? expectedActor}) async {
    final actor = _client.auth.currentSession?.user.id;
    final token = _client.auth.currentSession?.accessToken;
    if (actor == null || token == null || (expectedActor != null && actor != expectedActor)) {
      throw StateError('ログイン状態を確認して日報を開き直してください。');
    }
    var invalidated = false;
    final subscription = _client.auth.onAuthStateChange.listen((event) {
      if (event.session?.user.id != actor || event.session?.accessToken != token) { invalidated = true; }
    });
    void check() {
      if (invalidated || _client.auth.currentSession?.user.id != actor ||
          _client.auth.currentSession?.accessToken != token) {
        throw StateError('ログイン状態が変わりました。日報を開き直してください。');
      }
    }
    try {
      check();
      final raw = await _client.rpc(name, params: parameters);
      await Future<void>.delayed(Duration.zero);
      check();
      if (raw is! Map || raw['schema'] != 1 || raw['actor_id'] != actor) {
        throw StateError('共同日報の応答を確認できません。');
      }
      return raw;
    } on PostgrestException catch (error) {
      await Future<void>.delayed(Duration.zero);
      check();
      if (error.code == 'PT409' && SharedReportManagementHold.reasons.contains(error.message)) {
        throw SharedReportManagementHold(reasonCode: error.message);
      }
      rethrow;
    } finally { await subscription.cancel(); }
  }

  Future<SharedDailyReportContext> loadForSource(String sourceClockInId) async {
    final raw = await _rpc('read_my_shared_daily_report', {'p_source_clock_in_id': sourceClockInId});
    return SharedDailyReportContext.parse(raw, actorId: _client.auth.currentSession!.user.id,
      sourceClockInId: sourceClockInId);
  }
  Future<SharedDailyReportContext> loadReport(String reportId, {String? expectedActor}) async {
    final raw = await _rpc('read_shared_daily_report_context', {'p_report_id': reportId}, expectedActor: expectedActor);
    return SharedDailyReportContext.parse(raw, actorId: expectedActor ?? _client.auth.currentSession!.user.id, reportId: reportId);
  }
  Future<SharedDailyReportContext> startFinalizationEdit({required SharedDailyReportContext before,
    required String reason}) async {
    if (!before.explicitFinalizationRequired || !before.explicitFinalizationEditable ||
        before.explicitFinalizationCompleted || before.reportId == null ||
        before.expectedUpdatedAt == null || before.signatureScopeFingerprint == null) {
      throw StateError('確定前の日報を手直しできる状態を確認してください。');
    }
    final raw = await _rpc('start_shared_report_finalization_edit', {
      'p_report_id': before.reportId,
      'p_expected_updated_at': before.expectedUpdatedAt!.toUtc().toIso8601String(),
      'p_expected_signature_scope': before.signatureScopeFingerprint, 'p_reason': reason,
    }, expectedActor: before.actorId);
    final after = SharedDailyReportContext.parse(raw, actorId: before.actorId,
      companyId: before.companyId, reportId: before.reportId, workDate: before.workDate);
    if (!after.explicitFinalizationRequired || after.reporterSaved || after.supervisorSaved ||
        after.reportStatus != 'draft') {
      throw StateError('手直しの開始状態を確認できません。日報を再読み込みしてください。');
    }
    return after;
  }
  Future<SharedDailyReportContext> finalize({required SharedDailyReportContext before}) async {
    if (!before.canFinalize) { throw StateError('報告者・責任者のサインと勤務実績を確認してから保存してください。'); }
    final raw = await _rpc('finalize_shared_daily_report', {
      'p_report_id': before.reportId,
      'p_expected_updated_at': before.expectedUpdatedAt!.toUtc().toIso8601String(),
      'p_expected_signature_scope': before.signatureScopeFingerprint,
    }, expectedActor: before.actorId);
    final after = SharedDailyReportContext.parse(raw, actorId: before.actorId,
      companyId: before.companyId, reportId: before.reportId, workDate: before.workDate);
    if (!after.explicitFinalizationCompleted || after.reportStatus != 'signed') {
      throw StateError('給与・請求への反映と日報の確定を確認できません。再読み込みしてください。');
    }
    return after;
  }
  Future<SharedDailyReportContext> reuse(SharedDailyReportContext before) async {
    if (before.sourceClockInId == null) { throw StateError('本人の出退勤原本を確認してください。'); }
    final raw = await _rpc('reuse_my_shared_daily_report', {'p_source_clock_in_id': before.sourceClockInId}, expectedActor: before.actorId);
    return SharedDailyReportContext.parse(raw, actorId: before.actorId,
      companyId: before.companyId, workerId: before.workerId,
      workDate: before.workDate, sourceClockInId: before.sourceClockInId);
  }
  Future<SharedDailyReportContext> submit({required SharedDailyReportContext before,
    required String workDescription, required List<Map<String, dynamic>> workers,
    required String signerName, required Map<String, dynamic> signature,
  }) async {
    if (!before.enabled || before.sourceClockInId == null || before.reportId == null || before.expectedUpdatedAt == null || before.signatureScopeFingerprint == null) { throw StateError('共同日報の登録条件を確認してください。'); }
    final raw = await _rpc('submit_shared_daily_report', {
      'p_source_clock_in_id': before.sourceClockInId,
      'p_expected_updated_at': before.expectedUpdatedAt?.toUtc().toIso8601String(),
      'p_expected_signature_scope': before.signatureScopeFingerprint,
      'p_work_description': workDescription, 'p_workers': workers,
      'p_signer_name': signerName, 'p_signature': signature,
    }, expectedActor: before.actorId);
    return SharedDailyReportContext.parse(raw, actorId: before.actorId,
      companyId: before.companyId, workerId: before.workerId,
      workDate: before.workDate, sourceClockInId: before.sourceClockInId);
  }
  Future<SharedDailyReportContext> saveDocumentDraft({required SharedDailyReportContext before,
    required String workDescription, required List<Map<String, dynamic>> workers,
  }) async {
    if (!before.documentOnly || before.reporterSaved || before.supervisorSaved || before.reportId == null ||
        before.expectedUpdatedAt == null || before.signatureScopeFingerprint == null) {
      throw StateError('手直しする日報の状態を確認できません。再読み込みしてください。');
    }
    final raw = await _rpc('save_shared_report_document_draft', {
      'p_report_id': before.reportId,
      'p_expected_updated_at': before.expectedUpdatedAt!.toUtc().toIso8601String(),
      'p_expected_signature_scope': before.signatureScopeFingerprint,
      'p_work_description': workDescription, 'p_workers': workers,
    }, expectedActor: before.actorId);
    final after = SharedDailyReportContext.parse(raw, actorId: before.actorId,
      companyId: before.companyId, reportId: before.reportId, workDate: before.workDate);
    if (!after.documentOnly || after.reporterSaved || after.supervisorSaved) {
      throw StateError('手直しの保存結果を確認できません。再読み込みしてください。');
    }
    return after;
  }
  Future<SharedDailyReportContext> startDocumentEdit({required SharedDailyReportContext before,
    required String reason,
  }) async {
    if (!before.documentOnly || !before.documentEditable || before.reportId == null ||
        before.expectedUpdatedAt == null || before.signatureScopeFingerprint == null) {
      throw StateError('この日報を手直しできる状態を確認できません。再読み込みしてください。');
    }
    final raw = await _rpc('start_shared_report_document_edit', {
      'p_report_id': before.reportId,
      'p_expected_updated_at': before.expectedUpdatedAt!.toUtc().toIso8601String(),
      'p_expected_signature_scope': before.signatureScopeFingerprint, 'p_reason': reason,
    }, expectedActor: before.actorId);
    final after = SharedDailyReportContext.parse(raw, actorId: before.actorId,
      companyId: before.companyId, reportId: before.reportId, workDate: before.workDate);
    if (!after.documentOnly || after.reporterSaved || after.supervisorSaved || after.documentComplete) {
      throw StateError('手直しの開始結果を確認できません。再読み込みしてください。');
    }
    return after;
  }
  Future<SharedDailyReportContext> prepareFinancialResigning({
    required SharedDailyReportContext before,
    required List<SharedWorkerFactsTransitionInput> workers, required String reason,
  }) async {
    if (!before.financialResigningSupported || !before.canManageAttendance ||
        !before.documentOnly || before.reporterSaved || before.supervisorSaved ||
        before.reportId == null || before.expectedUpdatedAt == null || before.signatureScopeFingerprint == null) {
      throw StateError('勤務実績の連携は準備中です。サインを変更せず、管理者に確認してください。');
    }
    final ids = workers.map((item) => item.before.workerId).toSet();
    if (workers.isEmpty || workers.length > 100 || ids.length != workers.length ||
        ids.length != before.workRosterIds.length || !ids.containsAll(before.workRosterIds) ||
        reason.trim().isEmpty || reason.trim().length > 1000 ||
        workers.any((item) => item.before.actorId != before.actorId ||
          item.before.companyId != before.companyId || item.before.reportId != before.reportId ||
          !item.before.canManageAttendance || item.before.sourceBlocked ||
          (item.hours != null && (!item.hours!.isFinite || item.hours! < 0 || item.hours! > 24)))) {
      throw StateError('対象者全員の実際の勤務実績と確認理由を確認してください。');
    }
    final raw = await _rpc('prepare_shared_report_financial_resigning', {
      'p_report_id': before.reportId,
      'p_expected_updated_at': before.expectedUpdatedAt!.toUtc().toIso8601String(),
      'p_expected_signature_scope': before.signatureScopeFingerprint,
      'p_workers': workers.map((item) => item.toJson()).toList(), 'p_reason': reason.trim(),
    }, expectedActor: before.actorId);
    final after = SharedDailyReportContext.parse(raw, actorId: before.actorId,
      companyId: before.companyId, reportId: before.reportId, workDate: before.workDate);
    if (!after.financialTransitionPending || !after.financialTransitionValid ||
        after.documentOnly || after.reporterSaved || after.supervisorSaved || after.reportStatus != 'draft') {
      throw StateError('勤務実績の保存結果を確認できません。再読み込みしてください。');
    }
    return after;
  }
  Future<SharedDailyReportContext> collectApprovedSupervisor({required SharedDailyReportContext before,
    required String requestId, required String signerName, required Map<String, dynamic> signature,
  }) async {
    if (before.reportId == null || before.approvedEditRequestId != requestId || !before.canCollectSupervisor) {
      throw StateError('承認された編集と責任者サインの対象を確認してください。');
    }
    await _rpc('collect_approved_shared_report_supervisor_signature', {
      'p_report_id': before.reportId, 'p_request_id': requestId,
      'p_signer_name': signerName, 'p_signature': signature,
      'p_expected_updated_at': before.expectedUpdatedAt?.toUtc().toIso8601String(),
      'p_expected_signature_scope': before.signatureScopeFingerprint,
    }, expectedActor: before.actorId);
    return loadReport(before.reportId!, expectedActor: before.actorId);
  }
  Future<SharedDailyReportContext> collectSupervisor({required SharedDailyReportContext before,
    required String signerName, required Map<String, dynamic> signature,
  }) async {
    if (before.reportId == null || !before.canCollectSupervisor) { throw StateError('責任者サインの登録条件を確認してください。'); }
    return before.canManageAttendance
        ? manageSignature(before: before, role: 'supervisor', signerName: signerName, signature: signature)
        : _sign(before, 'collect_shared_report_supervisor_signature', {
            'p_report_id': before.reportId, 'p_source_clock_in_id': before.sourceClockInId,
            'p_signer_name': signerName, 'p_signature': signature,
            'p_expected_updated_at': before.expectedUpdatedAt?.toUtc().toIso8601String(),
            'p_expected_signature_scope': before.signatureScopeFingerprint,
          });
  }
  Future<SharedDailyReportContext> manageSignature({required SharedDailyReportContext before,
    required String role, required String signerName, required Map<String, dynamic> signature,
  }) {
    if (!before.enabled || !before.canManageAttendance || before.reportId == null ||
        !const ['representative', 'supervisor'].contains(role)) {
      throw StateError('勤怠管理の権限を確認してください。');
    }
    return _sign(before, 'manage_shared_report_signature', {
      'p_report_id': before.reportId, 'p_role': role, 'p_signer_name': signerName, 'p_signature': signature,
      'p_expected_updated_at': before.expectedUpdatedAt?.toUtc().toIso8601String(),
      'p_expected_signature_scope': before.signatureScopeFingerprint,
    });
  }
  Future<SharedDailyReportContext> _sign(SharedDailyReportContext before, String rpc, Map<String, dynamic> parameters) async {
    final raw = await _rpc(rpc, parameters, expectedActor: before.actorId);
    if (raw is! Map || raw['report_id'] != before.reportId || !const ['saved', 'already_saved'].contains(raw['state'])) {
      throw StateError('サインの保存結果を確認できません。');
    }
    return loadReport(before.reportId!, expectedActor: before.actorId);
  }
}



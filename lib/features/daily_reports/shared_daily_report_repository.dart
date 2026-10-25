import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

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
    this.pendingWorkerIds = const [], this.supervisorPendingReasons = const [],
  });
  final String actorId, companyId, state, reporterName;
  final String? workerId, reportId, sourceClockInId, clockOutId, reportStatus;
  final DateTime workDate;
  final DateTime? expectedUpdatedAt;
  final String? signatureScopeFingerprint;
  final Map<String, dynamic>? hoursAnnex;
  final Map<String, dynamic>? workBasis;
  final bool supervisorReady;
  final bool firstReporterCoversWorkOnly;
  final List<String> pendingWorkerIds, supervisorPendingReasons;
  final bool enabled, canManageAttendance, reporterSaved, supervisorSaved,
      sourceAttached;
  bool get signedFactsReadOnly => reporterSaved || supervisorSaved;
  bool get canAccessSupervisorCollection => enabled && !supervisorSaved &&
      (canManageAttendance || (reporterSaved && sourceClockInId != null));
  bool get canCollectSupervisor => canAccessSupervisorCollection && supervisorReady &&
      signatureScopeFingerprint != null &&
      !(hoursAnnex?['required'] == true &&
          (hoursAnnex?['enabled'] != true || hoursAnnex?['ready'] != true));
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
    for (final key in ['enabled', 'can_manage_attendance', 'reporter_saved', 'supervisor_saved', 'source_attached', 'supervisor_ready']) {
      if (row[key] is! bool) { invalid(); }
    }
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
    if (fingerprint != null) {
      if (work is! Map || work['contract_version'] != 2 || work['report'] is! Map || work['roster'] is! List) { invalid(); }
      final header = work['report'] as Map;
      if (header['id'] != report || header['company_id'] != company || header['work_date'] != dayRaw ||
          header['work_description'] is! String) { invalid(); }
      for (final key in ['site_id', 'route_assignment_id']) {
        if (header[key] != null && (header[key] is! String || !_uuid.hasMatch(header[key] as String))) { invalid(); }
      }
      if ((header['site_id'] == null) == (header['route_assignment_id'] == null)) { invalid(); }
      final roster = work['roster'] as List;
      if (roster.isEmpty || roster.length > 100 || roster.any((e) => e is! Map || e['worker_id'] is! String || !_uuid.hasMatch(e['worker_id'] as String))) { invalid(); }
      if (roster.map((e) => (e as Map)['worker_id']).toSet().length != roster.length) { invalid(); }
      workBasis = freeze(work) as Map<String, dynamic>;
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
      workBasis: workBasis,
      firstReporterCoversWorkOnly: row['first_reporter_covers_work_only'] == true,
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
    if (!before.enabled || before.sourceClockInId == null) { throw StateError('共同日報の登録条件を確認してください。'); }
    final raw = await _rpc('submit_shared_daily_report', {
      'p_source_clock_in_id': before.sourceClockInId,
      'p_expected_updated_at': before.expectedUpdatedAt?.toUtc().toIso8601String(),
      'p_work_description': workDescription, 'p_workers': workers,
      'p_signer_name': signerName, 'p_signature': signature,
    }, expectedActor: before.actorId);
    return SharedDailyReportContext.parse(raw, actorId: before.actorId,
      companyId: before.companyId, workerId: before.workerId,
      workDate: before.workDate, sourceClockInId: before.sourceClockInId);
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

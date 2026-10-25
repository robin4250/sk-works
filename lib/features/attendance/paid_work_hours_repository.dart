import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

/// Server-derived final-day scope. Hours are explicit; elapsed time is never
/// interpreted as a quantity by this client.
class PaidWorkHoursSnapshot {
  const PaidWorkHoursSnapshot({
    required this.actorId,
    required this.companyId,
    required this.workerId,
    required this.reportId,
    required this.workDate,
    required this.revision,
    required this.scopeFingerprint,
    required this.hoursRequired,
    required this.editable,
    required this.sourceBlocked,
    required this.inputScopeCurrent,
    required this.sourceReasons,
    this.hours,
    this.contractVersion = 1,
    this.workReportFrozen = false,
    this.firstReporterCoversWorkOnly = false,
    this.workBasisHash,
    this.supervisorFinalized = false,
  });

  final String actorId, companyId, workerId, reportId, scopeFingerprint;
  final DateTime workDate;
  final int revision;
  final bool hoursRequired, editable, sourceBlocked, inputScopeCurrent;
  final List<String> sourceReasons;
  final double? hours;
  final int contractVersion;
  final bool workReportFrozen, firstReporterCoversWorkOnly;
  final String? workBasisHash;
  final bool supervisorFinalized;

  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  factory PaidWorkHoursSnapshot.parse(
    Object? raw, {
    required String actorId,
    required String companyId,
    required String workerId,
    required String reportId,
  }) {
    Never invalid() => throw StateError('実勤務時間の設定情報を確認できません。再読込してください。');
    if (raw is! Map || raw['schema'] != 1) invalid();
    final row = Map<String, dynamic>.from(raw);
    for (final entry in <String, String>{
      'actor_id': actorId,
      'company_id': companyId,
      'worker_id': workerId,
      'report_id': reportId,
    }.entries) {
      if (!_uuid.hasMatch(entry.value) || row[entry.key] != entry.value) invalid();
    }
    final dateRaw = row['work_date'];
    if (dateRaw is! String || !RegExp(r'^20\d{2}-\d{2}-\d{2}$').hasMatch(dateRaw)) invalid();
    final day = DateTime.tryParse(dateRaw);
    if (day == null || day.toIso8601String().substring(0, 10) != dateRaw) invalid();
    final revision = row['revision'];
    if (revision is! int || revision < 0) invalid();
    final hash = row['scope_fingerprint'];
    if (hash is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) invalid();
    for (final key in ['required', 'editable', 'source_blocked', 'input_scope_current']) {
      if (row[key] is! bool) invalid();
    }
    final rawHours = row['hours'];
    double? hours;
    if (rawHours != null) {
      if (rawHours is! num || !rawHours.isFinite || rawHours < 0 || rawHours > 24) invalid();
      hours = rawHours.toDouble();
      if ((hours * 10000 - (hours * 10000).round()).abs() > 0.000001) invalid();
    }
    final reasons = row['source_reasons'];
    if (reasons is! List || reasons.length > 100 || reasons.any((e) => e is! String || e.length > 100)) invalid();
    if (row['editable'] == true && row['source_blocked'] == true) invalid();
    if ((row['source_blocked'] == true) != reasons.isNotEmpty) invalid();
    final contractVersion = row['contract_version'] ?? 1;
    if (contractVersion is! int || (contractVersion != 1 && contractVersion != 2)) invalid();
    if (contractVersion == 2 && (row['work_report_frozen'] is! bool ||
        row['first_reporter_covers_work_only'] != true || row['work_basis_sha256'] is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(row['work_basis_sha256'] as String) ||
        !const ['draft', 'signed'].contains(row['report_status']))) invalid();
    return PaidWorkHoursSnapshot(
      actorId: actorId, companyId: companyId, workerId: workerId,
      reportId: reportId, workDate: day, revision: revision,
      scopeFingerprint: hash, hoursRequired: row['required'] as bool,
      editable: row['editable'] as bool,
      sourceBlocked: row['source_blocked'] as bool,
      inputScopeCurrent: row['input_scope_current'] as bool,
      sourceReasons: List<String>.unmodifiable(reasons.cast<String>()), hours: hours,
      contractVersion: contractVersion,
      workReportFrozen: contractVersion == 2 && row['work_report_frozen'] == true,
      firstReporterCoversWorkOnly: contractVersion == 2,
      workBasisHash: contractVersion == 2 ? row['work_basis_sha256'] as String : null,
      supervisorFinalized: contractVersion == 2 && row['report_status'] == 'signed',
    );
  }
}

class PaidWorkHoursRepository {
  PaidWorkHoursRepository(this._client);
  final SupabaseClient _client;

  static PaidWorkHoursRepository? maybeCreate() =>
      !SupabaseBackend.isInitialized || SupabaseBackend.client.auth.currentUser == null
          ? null : PaidWorkHoursRepository(SupabaseBackend.client);

  Future<PaidWorkHoursSnapshot> _request({
    required String companyId,
    required String workerId,
    required String reportId,
    required String rpc,
    required Map<String, dynamic> parameters,
  }) async {
    final session = _client.auth.currentSession;
    final actor = session?.user.id;
    final token = session?.accessToken;
    if (actor == null || token == null) throw StateError('ログインが必要です。');
    var invalidated = false;
    // Retain emitted session evidence, including A→B→A before async delivery.
    final subscription = _client.auth.onAuthStateChange.listen((event) {
      if (event.session?.user.id != actor || event.session?.accessToken != token) {
        invalidated = true;
      }
    });
    void check() {
      if (invalidated || _client.auth.currentSession?.user.id != actor ||
          _client.auth.currentSession?.accessToken != token) {
        throw StateError('ログイン状態が変わりました。日報を開き直してください。');
      }
    }
    try {
      check();
      final raw = await _client.rpc(rpc, params: parameters);
      // Flush the SDK's asynchronous session events before accepting an
      // otherwise identical A→B→A current-session getter snapshot.
      await Future<void>.delayed(Duration.zero);
      check();
      return PaidWorkHoursSnapshot.parse(raw, actorId: actor,
        companyId: companyId, workerId: workerId, reportId: reportId);
    } finally {
      await subscription.cancel();
    }
  }

  Future<PaidWorkHoursSnapshot> load({
    required String companyId, required String workerId, required String reportId,
  }) => _request(companyId: companyId, workerId: workerId, reportId: reportId,
    rpc: 'read_checkout_paid_work_hours', parameters: {
      'p_report_id': reportId, 'p_worker_id': workerId,
    });

  Future<PaidWorkHoursSnapshot> save(PaidWorkHoursSnapshot before, String text) {
    final trimmed = text.trim();
    if (!RegExp(r'^(?:0|[1-9]\d?)(?:\.\d{1,4})?$').hasMatch(trimmed)) {
      throw FormatException('実勤務時間を0〜24の数値で入力してください。');
    }
    final hours = double.parse(trimmed);
    if (!hours.isFinite || hours > 24 || !before.editable || before.sourceBlocked) {
      throw FormatException('最終退勤後の日報に0〜24時間で入力してください。');
    }
    return _request(companyId: before.companyId, workerId: before.workerId,
      reportId: before.reportId, rpc: 'save_checkout_paid_work_hours', parameters: {
        'p_report_id': before.reportId, 'p_worker_id': before.workerId,
        'p_hours': hours, 'p_expected_revision': before.revision,
        'p_expected_scope': before.scopeFingerprint,
      });
  }
}

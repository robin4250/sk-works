import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import '../attendance/paid_work_hours_repository.dart';
import 'daily_report_company_allowance_selection.dart';
import 'daily_report_repository.dart';

/// Confirmed or explicitly labelled provisional values. Missing input is never
/// converted to zero by this model; only a user confirmation creates evidence.
class SharedWorkerFacts {
  const SharedWorkerFacts({required this.overtimeHours, required this.earlyHours,
    required this.nightHours, required this.workCategory, required this.allowanceAmount,
    required this.allowanceLabel, required this.companyAllowanceSelections,
    required this.legacyLabels, required this.vehicleId, required this.routeId,
    required this.odometerKm});

  final double overtimeHours, earlyHours, nightHours;
  final String workCategory;
  final int allowanceAmount;
  final String? allowanceLabel, legacyLabels, vehicleId, routeId;
  final double? odometerKm;
  final DailyReportCompanyAllowanceSelections companyAllowanceSelections;
  static final _uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');

  factory SharedWorkerFacts.parse(Object? raw) {
    Never invalid() => throw const FormatException('本人の勤務実績を確認できません。再読込してください。');
    const keys = {'schema', 'overtime_hours', 'early_hours', 'night_hours',
      'work_category', 'allowance_amount', 'allowance_label',
      'company_allowance_selections', 'company_allowance_legacy_labels',
      'vehicle_id', 'route_assignment_id', 'odometer_km'};
    if (raw is! Map || raw.length != keys.length || !raw.keys.every(keys.contains) || raw['schema'] != 1) { invalid(); }
    final row = Map<String, dynamic>.from(raw);
    double hours(String key) {
      final value = row[key];
      if (value is! num || !value.isFinite || value < 0 || value > 24 ||
          (value * 10000 - (value * 10000).round()).abs() > 0.000001) { invalid(); }
      return value.toDouble();
    }
    final category = row['work_category'];
    if (!const ['day', 'night', 'holiday', 'holiday_night'].contains(category)) { invalid(); }
    final amount = row['allowance_amount'];
    if (amount is! int || amount < 0 || amount > 2147483647) { invalid(); }
    String? text(String key) {
      final value = row[key];
      if (value == null) { return null; }
      if (value is! String || value.length > 1048576 || value.trim() != value || value.isEmpty) { invalid(); }
      return value;
    }
    String? id(String key) {
      final value = row[key];
      if (value == null) { return null; }
      if (value is! String || !_uuid.hasMatch(value)) { invalid(); }
      return value;
    }
    final vehicle = id('vehicle_id'), route = id('route_assignment_id');
    final distance = row['odometer_km'];
    if (distance != null && (distance is! num || !distance.isFinite || distance < 0 || distance > 999999999)) { invalid(); }
    if (vehicle == null && distance != null || vehicle != null && distance == null) { invalid(); }
    return SharedWorkerFacts(overtimeHours: hours('overtime_hours'), earlyHours: hours('early_hours'),
      nightHours: hours('night_hours'), workCategory: category as String, allowanceAmount: amount,
      allowanceLabel: text('allowance_label'), legacyLabels: text('company_allowance_legacy_labels'),
      companyAllowanceSelections: DailyReportCompanyAllowanceSelections.fromJson(row['company_allowance_selections']),
      vehicleId: vehicle, routeId: route, odometerKm: (distance as num?)?.toDouble());
  }

  factory SharedWorkerFacts.fromDraft(DailyReportWorkerDraft draft, {required String workCategory}) {
    if (draft.companyAllowanceSelections == null) {
      throw const FormatException('会社手当の選択状態を確認してください。');
    }
    return SharedWorkerFacts.parse({'schema': 1, 'overtime_hours': draft.overtimeHours,
        'early_hours': draft.earlyHours, 'night_hours': draft.nightHours,
        'work_category': workCategory, 'allowance_amount': draft.allowanceAmount,
        'allowance_label': draft.allowanceLabel.trim().isEmpty ? null : draft.allowanceLabel.trim(),
        'company_allowance_selections': draft.companyAllowanceSelections!.toJson(),
        'company_allowance_legacy_labels': null, 'vehicle_id': draft.vehicleId,
        'route_assignment_id': draft.routeId, 'odometer_km': draft.odometerKm});
  }

  Map<String, Object?> toJson() => {'schema': 1, 'overtime_hours': overtimeHours,
    'early_hours': earlyHours, 'night_hours': nightHours, 'work_category': workCategory,
    'allowance_amount': allowanceAmount, 'allowance_label': allowanceLabel,
    'company_allowance_selections': companyAllowanceSelections.toJson(),
    'company_allowance_legacy_labels': legacyLabels, 'vehicle_id': vehicleId,
    'route_assignment_id': routeId, 'odometer_km': odometerKm};

  /// Legacy labels are server-derived and are never writable client input.
  Map<String, Object?> toConfirmationJson() => toJson()..remove('company_allowance_legacy_labels');

  DailyReportWorkerDraft toDraft({required String workerId, required String workerName,
    DailyReportWorkerDraft? template}) {
    if (template != null && template.workerId != workerId) {
      throw const FormatException('本人の勤務実績の対象が一致しません。');
    }
    final sameVehicle = template?.vehicleId == vehicleId && template?.routeId == routeId && template?.odometerKm == odometerKm;
    return DailyReportWorkerDraft(workerId: workerId, workerName: workerName,
      overtimeHours: overtimeHours, earlyHours: earlyHours, nightHours: nightHours,
      allowanceAmount: allowanceAmount, allowanceLabel: allowanceLabel ?? '',
      companyAllowanceSelections: companyAllowanceSelections, vehicleId: vehicleId,
      vehicleName: sameVehicle ? template?.vehicleName : null, routeId: routeId,
      routeName: sameVehicle ? template?.routeName : null, odometerKm: odometerKm,
      sourceClockInId: template?.sourceClockInId, sourceClockOutAt: template?.sourceClockOutAt,
      meterManaged: sameVehicle && (template?.meterManaged ?? false),
      meterEventId: sameVehicle ? template?.meterEventId : null,
      meterSourceClockInId: sameVehicle ? template?.meterSourceClockInId : null,
      previousOdometerKm: sameVehicle ? template?.previousOdometerKm : null,
      tripDistanceKm: sameVehicle ? template?.tripDistanceKm : null);
  }
}

/// Explicit reviewed input for one atomic document-to-financial transition.
/// Reuses the source snapshot and normalized facts; never derives a category.
class SharedWorkerFactsTransitionInput {
  const SharedWorkerFactsTransitionInput({required this.before, required this.facts, this.hours});
  final SharedWorkerFactsSnapshot before;
  final SharedWorkerFacts facts;
  final double? hours;
  Map<String, dynamic> toJson() => {
    'worker_id': before.workerId, 'facts': facts.toConfirmationJson(), 'hours': hours,
    'expected_revision': before.revision, 'expected_scope': before.scopeFingerprint,
  };
}

class SharedWorkerFactsSnapshot {
  const SharedWorkerFactsSnapshot({required this.scope, required this.facts,
    required this.proposedFacts, required this.confirmed, required this.current,
    required this.isOwnWorker, required this.canManageAttendance,
    required this.hoursRequiredOutsideCurrentReport});
  final PaidWorkHoursSnapshot scope;
  final SharedWorkerFacts? facts, proposedFacts;
  final bool confirmed, current, isOwnWorker, canManageAttendance;
  final bool hoursRequiredOutsideCurrentReport;
  String get actorId => scope.actorId;
  String get companyId => scope.companyId;
  String get workerId => scope.workerId;
  String get reportId => scope.reportId;
  int get revision => scope.revision;
  String get scopeFingerprint => scope.scopeFingerprint;
  String? get workBasisHash => scope.workBasisHash;
  bool get editable => scope.editable;
  bool get sourceBlocked => scope.sourceBlocked;
  double? get hours => scope.hours;
  bool get hoursRequired => scope.hoursRequired;

  factory SharedWorkerFactsSnapshot.parse(Object? raw, {required String actorId,
    required String companyId, required String workerId, required String reportId}) {
    final scope = PaidWorkHoursSnapshot.parse(raw, actorId: actorId, companyId: companyId,
      workerId: workerId, reportId: reportId);
    Never invalid() => throw const FormatException('本人の勤務実績の確認状態を取得できません。');
    if (scope.contractVersion != 2 || raw is! Map) { invalid(); }
    for (final key in ['facts_confirmed', 'facts_current', 'own_worker', 'management_confirmation_available',
      'hours_required_outside_current_report']) {
      if (raw[key] is! bool) { invalid(); }
    }
    final facts = raw['worker_facts'] == null ? null : SharedWorkerFacts.parse(raw['worker_facts']);
    final proposed = raw['proposed_worker_facts'] == null ? null : SharedWorkerFacts.parse(raw['proposed_worker_facts']);
    if (raw['facts_confirmed'] == true && facts == null || raw['facts_current'] == true && raw['facts_confirmed'] != true) { invalid(); }
    return SharedWorkerFactsSnapshot(scope: scope, facts: facts, proposedFacts: proposed,
      confirmed: raw['facts_confirmed'] as bool, current: raw['facts_current'] as bool,
      isOwnWorker: raw['own_worker'] as bool, canManageAttendance: raw['management_confirmation_available'] as bool,
      hoursRequiredOutsideCurrentReport: raw['hours_required_outside_current_report'] as bool);
  }
}

class SharedWorkerFactsRepository {
  SharedWorkerFactsRepository(this._client);
  final SupabaseClient _client;
  static SharedWorkerFactsRepository? maybeCreate() =>
      !SupabaseBackend.isInitialized || SupabaseBackend.client.auth.currentUser == null
          ? null : SharedWorkerFactsRepository(SupabaseBackend.client);

  static String? _sessionKey(Session? session) {
    if (session == null) { return null; }
    try {
      final parts = session.accessToken.split('.');
      if (parts.length != 3) { return null; }
      final claims = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      if (claims is! Map || claims['sub'] != session.user.id || claims['session_id'] is! String ||
          !SharedWorkerFacts._uuid.hasMatch(claims['session_id'] as String)) { return null; }
      return '${session.user.id}/${claims['session_id']}';
    } on Object {
      return null;
    }
  }

  Future<SharedWorkerFactsSnapshot> _request({required String companyId,
    required String workerId, required String reportId, required String rpc,
    required Map<String, dynamic> parameters}) async {
    final session = _client.auth.currentSession;
    final actor = session?.user.id, key = _sessionKey(session);
    if (actor == null || key == null) { throw StateError('ログインが必要です。'); }
    var invalidated = false;
    final subscription = _client.auth.onAuthStateChange.listen((event) {
      if (_sessionKey(event.session) != key) { invalidated = true; }
    });
    void check() {
      if (invalidated || _sessionKey(_client.auth.currentSession) != key) {
        throw StateError('ログイン状態が変わりました。日報を開き直してください。');
      }
    }
    try {
      check();
      final raw = await _client.rpc(rpc, params: parameters);
      await Future<void>.delayed(Duration.zero);
      check();
      return SharedWorkerFactsSnapshot.parse(raw, actorId: actor, companyId: companyId,
        workerId: workerId, reportId: reportId);
    } on PostgrestException catch (error) {
      if (error.code == 'PT409' || error.code == '40001') {
        throw StateError('勤務実績が更新されました。再読込して確認してください。');
      }
      if (error.code == '42501') {
        throw StateError('この勤務実績を登録する権限を確認できません。');
      }
      throw StateError('勤務実績の取得・保存結果を確認できません。再読込してください。');
    } finally {
      await subscription.cancel();
    }
  }

  Future<SharedWorkerFactsSnapshot> load({required String companyId,
    required String reportId, required String workerId}) => _request(companyId: companyId,
      reportId: reportId, workerId: workerId, rpc: 'read_shared_worker_facts',
      parameters: {'p_report_id': reportId, 'p_worker_id': workerId});

  Future<SharedWorkerFactsSnapshot> confirm(SharedWorkerFactsSnapshot before,
    SharedWorkerFacts facts, {double? hours, String? managementReason}) {
    // Prospective selection replaces this report's prior selections; the server
    // independently resolves registered units and quantities.
    final valid = SharedWorkerFacts.parse(facts.toJson());
    final requiresHours = before.hoursRequiredOutsideCurrentReport ||
        valid.companyAllowanceSelections.items.any((item) => item.unit == 'hour');
    final reason = managementReason?.trim();
    final managed = reason != null && reason.isNotEmpty;
    if (managementReason != null && !managed ||
        managed && (!before.canManageAttendance || reason.length > 2000) ||
        !managed && !before.editable || before.sourceBlocked ||
        hours != null && (!hours.isFinite || hours < 0 || hours > 24 ||
          (hours * 10000 - (hours * 10000).round()).abs() > 0.000001) ||
        requiresHours && hours == null) {
      throw const FormatException('退勤記録と本人の勤務実績を確認してください。');
    }
    return _request(companyId: before.companyId, workerId: before.workerId,
      reportId: before.reportId, rpc: managed ? 'confirm_managed_shared_worker_facts' : 'confirm_shared_worker_facts',
      parameters: {'p_report_id': before.reportId, 'p_worker_id': before.workerId,
        'p_facts': valid.toConfirmationJson(), 'p_hours': hours,
        'p_expected_revision': before.revision, 'p_expected_scope': before.scopeFingerprint,
        if (managed) 'p_reason': reason});
  }
}


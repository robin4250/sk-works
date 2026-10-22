import 'dart:async';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/supabase_backend.dart';
import 'company_common_allowance_repository.dart';
import 'company_common_calculation_resolution.dart';
import 'company_common_canonical_publication_approval.dart';
import 'company_common_canonical_publication_command.dart';
import 'company_common_payroll_publication_repository.dart';

bool _count(Object? value) => value is int && value >= 0 && value <= 100;
const _scopeStatuses = {'target_new_scope', 'target_draft', 'excluded_manual', 'excluded_finalized', 'unresolved'};
List<Map<String, dynamic>> _scopes(Object? raw) {
  if (raw is! List || raw.length > 100) throw const FormatException('給与の対象を確認できません');
  final ids = <String>{};
  return List.unmodifiable(raw.map((entry) {
    if (entry is! Map || !canonicalPublicationUuid(entry['worker_id']) ||
        entry['month'] is! String ||
        !RegExp(r'^\d{4}-(0[1-9]|1[0-2])-01$').hasMatch(entry['month'] as String) ||
        !_scopeStatuses.contains(entry['status']) ||
        !ids.add('${entry['worker_id']}/${entry['month']}')) {
      throw const FormatException('給与の対象が一致しません');
    }
    return canonicalPublicationJsonCopy(entry) as Map<String, dynamic>;
  }));
}

class CommonPayrollCanonicalPublicationPreview {
  CommonPayrollCanonicalPublicationPreview._({required this.base, required this.token,
    required this.ready, required this.activationRequired, required this.activationScope,
    required this.activationMode, required this.activationBlockers, required this.targetCount,
    required this.excludedCount, required this.unresolvedCount, required this.legacyCount,
    required this.scopes, required this.timeline});
  final Map<String, dynamic> base;
  final String token;
  final bool ready, activationRequired;
  final String activationScope, activationMode;
  final List<String> activationBlockers;
  final int targetCount, excludedCount, unresolvedCount, legacyCount;
  final List<Map<String, dynamic>> scopes;
  final CommonPayrollPublicationState timeline;
  factory CommonPayrollCanonicalPublicationPreview.parse(Object? raw, Map<String, dynamic> expectedBase) {
    if (raw is! Map || raw['contract_version'] != 3 || raw['ready'] is! bool ||
        raw['activation_required'] is! bool || raw['preview_token'] is! String ||
        !const ['payroll_type', 'legacy_company'].contains(raw['activation_scope']) ||
        !const ['per_type', 'legacy_global'].contains(raw['activation_mode']) ||
        (raw['activation_scope'] == 'payroll_type') != (raw['activation_mode'] == 'per_type') ||
        raw['ready'] == true && raw['activation_scope'] == 'legacy_company' && raw['activation_required'] == true ||
        raw['activation_blockers'] is! List ||
        (raw['activation_blockers'] as List).length > 10 ||
        (raw['activation_blockers'] as List).any((code) => code is! String || code.isEmpty || code.length > 160) ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(raw['preview_token'] as String) ||
        !_count(raw['target_count']) || !_count(raw['excluded_count']) ||
        !_count(raw['unresolved_count']) || raw['items'] is! List ||
        canonicalPublicationJson(raw['command_base']) != canonicalPublicationJson(expectedBase)) {
      throw const FormatException('給与反映の対象を確認できません');
    }
    final scopes = _scopes(raw['scopes']);
    int count(Set<String> statuses) => scopes.where((s) => statuses.contains(s['status'])).length;
    if (count({'target_new_scope', 'target_draft'}) != raw['target_count'] ||
        count({'excluded_manual', 'excluded_finalized'}) != raw['excluded_count'] ||
        count({'unresolved'}) != raw['unresolved_count'] ||
        raw['ready'] != (raw['unresolved_count'] == 0 && (raw['activation_blockers'] as List).isEmpty)) {
      throw const FormatException('給与反映の件数が一致しません');
    }
    final base = canonicalPublicationJsonCopy(expectedBase) as Map<String, dynamic>;
    // Reuse exact command validation before presenting any approval.
    CommonPayrollCanonicalPublicationCommand.fromParams({...base,
      'p_request_id': '00000000-0000-0000-0000-000000000001',
      'p_preview_token': raw['preview_token'], 'p_approve_activation': false,
      'p_activation_scope': raw['activation_scope'],
    });
    final timeline = CommonPayrollPublicationState.parse(raw['timeline'], base['p_company_id'] as String);
    if (timeline.timelineVersion != base['p_timeline_version'] ||
        timeline.commonVersion != base['p_common_version'] ||
        canonicalPublicationJson(jsonDecode(timeline.commonSourceJson)) != canonicalPublicationJson(base['p_common_source'])) {
      throw const FormatException('給与反映の設定が更新されています');
    }
    final legacyCount = (raw['items'] as List).where((item) => item is Map && item['origin'] == 'company_legacy').length;
    if (legacyCount != (base['p_legacy_quantities'] as List).length) {
      throw const FormatException('共通手当の対象が一致しません');
    }
    return CommonPayrollCanonicalPublicationPreview._(base: base, token: raw['preview_token'] as String,
      ready: raw['ready'] as bool, activationRequired: raw['activation_required'] as bool,
      activationScope: raw['activation_scope'] as String, activationMode: raw['activation_mode'] as String,
      activationBlockers: List<String>.unmodifiable((raw['activation_blockers'] as List).cast<String>()),
      targetCount: raw['target_count'] as int, excludedCount: raw['excluded_count'] as int,
      unresolvedCount: raw['unresolved_count'] as int, legacyCount: legacyCount,
      scopes: scopes, timeline: timeline);
  }
  CommonPayrollCanonicalPublicationCommand approve({required bool activation, required bool selectedDays}) {
    if (!ready || !timeline.canEdit || unresolvedCount != 0 ||
        activationRequired && !activation || legacyCount > 0 && !selectedDays) {
      throw StateError('給与反映の確認が必要です');
    }
    return CommonPayrollCanonicalPublicationCommand.fromParams({...base,
      'p_request_id': CommonPayrollCanonicalPublicationCommand.newRequestId(),
      'p_preview_token': token, 'p_approve_activation': activation,
      'p_activation_scope': activationScope,
    });
  }
  CommonPayrollCanonicalApprovalPreview get approvalView {
    final reasons = <String>{};
    for (final code in activationBlockers) {
      reasons.add(code == 'legacy_global_boundary_advance_requires_review'
        ? '既存の適用開始月は前倒しできません。開始月を確認してください。'
        : '適用開始月の設定を確認してください');
    }
    for (final scope in scopes) {
      if (scope['status'] == 'excluded_manual') reasons.add('手動設定の給与は保持します');
      if (scope['status'] == 'excluded_finalized') reasons.add('確定済み給与は保持します');
      final rawReasons = scope['reasons'];
      if (rawReasons is List) {
        for (final reason in rawReasons.whereType<Map>()) {
          reasons.add(CompanyCommonCalculationResolution.reasonLabel(Map<String, dynamic>.from(reason)));
        }
      }
    }
    return CommonPayrollCanonicalApprovalPreview(
      payrollTypeLabel: const {'daily': '日給', 'hourly': '時給', 'monthly': '月給'}[base['p_payroll_type']]!,
      startsOn: DateTime.parse(base['p_starts_on'] as String), targetCount: targetCount,
      excludedCount: excludedCount, unresolvedCount: unresolvedCount, legacyCount: legacyCount,
      activationRequired: activationRequired, readyToPublish: ready, reasons: List.unmodifiable(reasons));
  }
}

class CommonPayrollCanonicalPublicationResult {
  CommonPayrollCanonicalPublicationResult._(this.timeline, this.targetCount, this.excludedCount, this.scopes);
  final CommonPayrollPublicationState timeline;
  final int targetCount, excludedCount;
  final List<Map<String, dynamic>> scopes;
  factory CommonPayrollCanonicalPublicationResult.parse(Object? raw, CommonPayrollCanonicalPublicationCommand command) {
    if (raw is! Map || raw['contract_version'] != 3 || raw['company_id'] != command.companyId ||
        raw['request_id'] != command.requestId || raw['payroll_type'] != command.payrollType ||
        raw['starts_on'] != command.startsOn || raw['publication_version'] != (command.params['p_timeline_version'] as int) + 1 ||
        !_count(raw['recalculated_scopes']) || !_count(raw['excluded_scopes']) ||
        raw['unresolved_scopes'] != 0 || raw['activation_changed'] is! bool) {
      throw const FormatException('給与反映の結果が一致しません');
    }
    if (raw['activation_scope'] != command.activationScope ||
        raw['activation_mode'] != (command.activationScope == 'payroll_type' ? 'per_type' : 'legacy_global') ||
        raw['activation_changed'] == true && (!command.approvesActivation || command.activationScope != 'payroll_type')) {
      throw const FormatException('給与反映の適用範囲が一致しません');
    }
    final scopes = _scopes(raw['scopes']);
    final targets = scopes.where((s) => const {'target_new_scope', 'target_draft'}.contains(s['status'])).toList();
    final excluded = scopes.where((s) => const {'excluded_manual', 'excluded_finalized'}.contains(s['status'])).length;
    if (targets.length != raw['recalculated_scopes'] || excluded != raw['excluded_scopes'] ||
        scopes.length != targets.length + excluded ||
        targets.any((s) => !const {'verified', 'no_salary_without_attendance'}.contains(s['readback_status']) ||
          s['readback_status'] == 'verified' && (s['statement_md5_after'] is! String ||
            !RegExp(r'^[0-9a-f]{32}$').hasMatch(s['statement_md5_after'] as String)))) {
      throw const FormatException('給与反映後の照合結果を確認できません');
    }
    final timeline = CommonPayrollPublicationState.parse(raw['timeline'], command.companyId);
    if (timeline.timelineVersion != raw['publication_version'] ||
        !timeline.entries.any((entry) => entry['version'] == raw['publication_version'] &&
          entry['request_id'] == command.requestId && entry['starts_on'] == command.startsOn &&
          entry['payroll_type'] == command.payrollType)) {
      throw const FormatException('給与反映の適用月が一致しません');
    }
    return CommonPayrollCanonicalPublicationResult._(timeline, targets.length, excluded, scopes);
  }
  String get message => '未確定給与への反映を登録しました。対象 $targetCount件・除外 $excludedCount件。';
}

abstract interface class CommonPayrollCanonicalPublicationRepository {
  String? get actorId;
  String? get sessionKey;
  Stream<String?> get sessionChanges;
  Future<bool> available();
  Future<CommonPayrollPublicationState> read(String companyId);
  Future<CommonPayrollCanonicalPublicationPreview> preview(Map<String, dynamic> params);
  Future<CommonPayrollCanonicalPublicationResult> publish(CommonPayrollCanonicalPublicationCommand command);
  Future<CommonPayrollCanonicalPublicationResult?> receipt(CommonPayrollCanonicalPublicationCommand command);
}

class SupabaseCommonPayrollCanonicalPublicationRepository implements CommonPayrollCanonicalPublicationRepository {
  SupabaseCommonPayrollCanonicalPublicationRepository(this._client);
  final SupabaseClient _client;
  String? _verifiedSession;
  static SupabaseCommonPayrollCanonicalPublicationRepository? maybeCreate() =>
      SupabaseBackend.isInitialized && SupabaseBackend.client.auth.currentSession != null
          ? SupabaseCommonPayrollCanonicalPublicationRepository(SupabaseBackend.client) : null;
  @override String? get actorId => _client.auth.currentUser?.id;
  @override String? get sessionKey => _client.auth.currentSession?.accessToken;
  @override Stream<String?> get sessionChanges => _client.auth.onAuthStateChange.map((e) => e.session?.accessToken);
  Future<Object?> _call(String name, Map<String, dynamic> args, {bool probe = false}) async {
    final token = sessionKey, actor = actorId;
    if (token == null || actor == null || !probe && _verifiedSession != token) {
      throw StateError('給与反映の準備を確認してください');
    }
    var revoked = false;
    final subscription = _client.auth.onAuthStateChange.listen((e) {
      if (e.session?.accessToken != token || e.session?.user.id != actor) revoked = true;
    }, onError: (Object _) => revoked = true);
    try {
      final value = await _client.rpc(name, params: args).setHeader('Authorization', 'Bearer $token');
      if (revoked || sessionKey != token || actorId != actor) throw StateError('ログイン情報が変更されました');
      return value;
    } finally { await subscription.cancel(); }
  }
  @override Future<bool> available() async {
    _verifiedSession = null;
    final token = sessionKey;
    try {
      final value = await _call('company_common_payroll_publication_v2_contract_version', {}, probe: true);
      if (value is! int || value != 3 || token == null || sessionKey != token) return false;
      _verifiedSession = token;
      return true;
    } catch (_) { return false; }
  }
  @override Future<CommonPayrollPublicationState> read(String companyId) async => CommonPayrollPublicationState.parse(
    await _call('read_company_common_payroll_publications', {'p_company_id': companyId}), companyId);
  @override Future<CommonPayrollCanonicalPublicationPreview> preview(Map<String, dynamic> params) async {
    final original = canonicalPublicationJsonCopy(params) as Map<String, dynamic>;
    return CommonPayrollCanonicalPublicationPreview.parse(
      await _call('preview_company_common_payroll_v2', original), original);
  }
  @override Future<CommonPayrollCanonicalPublicationResult> publish(CommonPayrollCanonicalPublicationCommand command) async =>
      CommonPayrollCanonicalPublicationResult.parse(await _call('publish_company_common_payroll_v2', command.params), command);
  @override Future<CommonPayrollCanonicalPublicationResult?> receipt(CommonPayrollCanonicalPublicationCommand command) async {
    final raw = await _call('read_company_common_payroll_publish_receipt_v2', command.receiptParams);
    if (raw is! Map || raw['contract_version'] != 3 || raw['found'] is! bool) {
      throw const FormatException('給与反映の結果を確認できません');
    }
    return raw['found'] == true ? CommonPayrollCanonicalPublicationResult.parse(raw['result'], command) : null;
  }
}

Map<String, dynamic> canonicalCommonPayrollPreviewParams(
    CompanyCommonAllowanceState settings, CommonPayrollPublicationState timeline,
    String payrollType, String startsOn) {
  if (!settings.canEdit || !timeline.canEdit || settings.companyId != timeline.companyId ||
      settings.version != timeline.commonVersion ||
      canonicalPublicationJson(settings.expectedSource) != canonicalPublicationJson(jsonDecode(timeline.commonSourceJson))) {
    throw StateError('保存済みの共通手当を再読み込みしてください');
  }
  final quantities = <Map<String, dynamic>>[];
  for (final ref in settings.legacyRefs) {
    if (ref['amount_yen'] is int && (ref['amount_yen'] as int) > 0 &&
        ref['name'] is String && (ref['name'] as String).trim().isNotEmpty) {
      quantities.add({'id': ref['id'], 'generation': ref['generation'], 'source_unit': ref['source_unit'],
        'basis': CommonPayrollCanonicalPublicationCommand.quantityBasis,
        'aliases': [ref['name']]});
    }
  }
  final base = <String, dynamic>{'p_company_id': settings.companyId, 'p_payroll_type': payrollType,
    'p_starts_on': startsOn, 'p_common_version': settings.version,
    'p_common_source': settings.expectedSource, 'p_timeline_version': timeline.timelineVersion,
    'p_legacy_quantities': quantities,
    'p_individual_reconciliation': CommonPayrollCanonicalPublicationCommand.reconciliation};
  CommonPayrollCanonicalPublicationCommand.fromParams({...base,
    'p_request_id': '00000000-0000-0000-0000-000000000001',
    'p_preview_token': List.filled(64, '0').join(), 'p_approve_activation': false,
    'p_activation_scope': 'payroll_type'});
  return canonicalPublicationJsonCopy(base) as Map<String, dynamic>;
}

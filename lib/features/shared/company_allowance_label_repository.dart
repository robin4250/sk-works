import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

/// A current company definition, not a dated quantity, personal override or
/// evidence that an allowance has already been applied to payroll.
class CompanyAllowanceLabel {
  const CompanyAllowanceLabel({required this.id, required this.name,
    required this.unit, required this.generation, this.origin = 'company_legacy',
    this.payrollType = 'all', this.section = 'earning', this.displayUnit = '',
    this.legacySlot, this.registrationVersion});
  final String? id;
  final String name, unit, origin, payrollType, section, displayUnit;
  final int? generation, legacySlot, registrationVersion;
  bool get selectable => id != null && registrationVersion != null &&
      (origin != 'company_legacy' || generation != null);
}

class CompanyAllowanceLabelSnapshot {
  const CompanyAllowanceLabelSnapshot({required this.companyId,
    required this.version, required this.items, this.legacyVersion});
  final String companyId;
  /// Version of the additional common-item catalog; legacy identity is separate.
  final int version;
  final int? legacyVersion;
  final List<CompanyAllowanceLabel> items;

  factory CompanyAllowanceLabelSnapshot.parse(Object? raw, String companyId) {
    bool integer(Object? v, {bool zero = false}) => v is int &&
        v >= (zero ? 0 : 1) && v <= 9007199254740990;
    bool uuid(Object? v) => v is String &&
        RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(v);
    if (raw is! Map || raw['contract_version'] != 1 ||
        raw['company_id'] != companyId || raw['registration_scope'] != 'current' ||
        raw['source_versions'] is! Map || raw['items'] is! List ||
        (raw['items'] as List).length > 303) {
      throw const FormatException('会社の登録手当名を確認できません');
    }
    final versions = raw['source_versions'] as Map;
    if (!integer(versions['common_version'], zero: true) ||
        versions['legacy_version'] != null && !integer(versions['legacy_version'])) {
      throw const FormatException('会社手当名の版を確認できません');
    }
    final items = <CompanyAllowanceLabel>[];
    final keys = <String>{};
    for (final item in raw['items'] as List) {
      if (item is! Map || !const ['company_legacy', 'company_common'].contains(item['origin']) ||
          item['name'] is! String || (item['name'] as String).trim().isEmpty ||
          (item['name'] as String).length > 4096 ||
          !const ['earning', 'deduction'].contains(item['section']) ||
          !const ['hour', 'day', 'month'].contains(item['unit']) ||
          item['display_unit'] is! String || (item['display_unit'] as String).length > 256 ||
          item['id'] != null && !uuid(item['id']) ||
          item['generation'] != null && !integer(item['generation']) ||
          item['registration_version'] != null && !integer(item['registration_version'], zero: true)) {
        throw const FormatException('会社の登録手当名の形式を確認できません');
      }
      final legacy = item['origin'] == 'company_legacy';
      if (legacy
          ? item['payroll_type'] != 'all' || item['section'] != 'earning' ||
            item['unit'] != 'day' || !const [1, 2, 3].contains(item['legacy_slot']) ||
            item['registration_version'] != versions['legacy_version'] ||
            (item['id'] == null) != (item['generation'] == null)
          : !const ['daily', 'hourly', 'monthly'].contains(item['payroll_type']) ||
            item['legacy_slot'] != null || item['generation'] != null ||
            !uuid(item['id']) || item['registration_version'] != versions['common_version']) {
        throw const FormatException('会社手当名の登録元を確認できません');
      }
      final key = legacy ? 'legacy/${item['legacy_slot']}' : 'common/${item['id']}';
      if (!keys.add(key)) throw const FormatException('会社手当の登録元が重複しています');
      items.add(CompanyAllowanceLabel(id: item['id'] as String?,
        name: item['name'] as String, unit: item['unit'] as String,
        generation: item['generation'] as int?, origin: item['origin'] as String,
        payrollType: item['payroll_type'] as String, section: item['section'] as String,
        displayUnit: item['display_unit'] as String, legacySlot: item['legacy_slot'] as int?,
        registrationVersion: item['registration_version'] as int?));
    }
    return CompanyAllowanceLabelSnapshot(companyId: companyId,
      version: versions['common_version'] as int,
      legacyVersion: versions['legacy_version'] as int?, items: List.unmodifiable(items));
  }
}

abstract interface class CompanyAllowanceLabelSource {
  Future<CompanyAllowanceLabelSnapshot> read(String companyId);
}

/// The new names-only RPC covers all current legacy/additional company items.
/// It never falls back to the old three-slot endpoint and claims completeness.
class SupabaseCompanyAllowanceLabelRepository implements CompanyAllowanceLabelSource {
  SupabaseCompanyAllowanceLabelRepository(SupabaseClient client)
      : _client = client, _invoke = null, _actor = null, _session = null;
  SupabaseCompanyAllowanceLabelRepository.forTesting({
    required Future<Object?> Function(String, Map<String, dynamic>) invoke,
    required String? Function() actor, required String? Function() sessionKey,
  }) : _client = null, _invoke = invoke, _actor = actor, _session = sessionKey;
  final SupabaseClient? _client;
  final Future<Object?> Function(String, Map<String, dynamic>)? _invoke;
  final String? Function()? _actor, _session;
  String? get _actorId => _actor?.call() ?? _client?.auth.currentUser?.id;
  String? get _token => _session?.call() ?? _client?.auth.currentSession?.accessToken;

  static SupabaseCompanyAllowanceLabelRepository? maybeCreate() =>
      SupabaseBackend.isInitialized && SupabaseBackend.client.auth.currentSession != null
          ? SupabaseCompanyAllowanceLabelRepository(SupabaseBackend.client) : null;

  @override Future<CompanyAllowanceLabelSnapshot> read(String companyId) async {
    final actor = _actorId, token = _token;
    if (companyId.isEmpty || actor == null || token == null || token.isEmpty ||
        (_client != null && _client.auth.currentSession?.isExpired != false)) {
      throw StateError('会社手当名の本人確認が必要です');
    }
    final args = <String, dynamic>{'p_company_id': companyId};
    final raw = _invoke != null
        ? await _invoke('read_company_registered_allowance_labels', args)
        : await _client!.rpc('read_company_registered_allowance_labels', params: args)
            .setHeader('Authorization', 'Bearer $token')
            .timeout(const Duration(seconds: 15));
    if (_actorId != actor || _token != token ||
        (_client != null && _client.auth.currentSession?.isExpired != false)) {
      throw StateError('ログイン状態が変わりました。手当名を再読み込みしてください');
    }
    return CompanyAllowanceLabelSnapshot.parse(raw, companyId);
  }
}

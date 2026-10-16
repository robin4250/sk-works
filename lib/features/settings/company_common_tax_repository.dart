import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

const _stateKeys = {'contract_version', 'company_id', 'can_edit', 'version',
  'expected_source', 'tax_rate', 'welfare_rate', 'legacy_refs', 'items'};
const _sourceKeys = {'legacy_adopted', 'legacy_version', 'legacy_slots', 'tax_rate', 'welfare_rate'};
const _payloadKeys = {'operation', 'expected_version', 'expected_source', 'tax_rate', 'welfare_rate'};

String commonTaxUuid(String value) {
  if (!RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(value)) {
    throw const FormatException('会社設定の対象を確認できません');
  }
  return value.toLowerCase();
}
Map<String, dynamic> commonTaxObject(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('税率設定を確認できません');
  }
  return Map<String, dynamic>.from(value);
}
bool commonTaxEqual(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length && a.keys.every((key) => b.containsKey(key) && commonTaxEqual(a[key], b[key]));
  }
  if (a is List && b is List) {
    return a.length == b.length && List.generate(a.length, (i) => i).every((i) => commonTaxEqual(a[i], b[i]));
  }
  return a == b;
}
Object? _freeze(Object? value) {
  if (value is Map) return Map<String, dynamic>.unmodifiable({for (final entry in value.entries) entry.key as String: _freeze(entry.value)});
  if (value is List) return List<Object?>.unmodifiable(value.map(_freeze));
  if (value == null || value is String || value is bool || (value is num && value.isFinite)) return value;
  throw const FormatException('税率設定の保存情報を確認できません');
}
Map<String, dynamic> _source(Object? value) {
  final source = commonTaxObject(value);
  if (source.length != _sourceKeys.length || !source.keys.every(_sourceKeys.contains) ||
      source['legacy_adopted'] is! bool || source['legacy_version'] is! int || source['legacy_version'] < 0 ||
      source['legacy_version'] > 9007199254740991 || source['legacy_slots'] is! List ||
      (source['legacy_slots'] as List).length != 3 || utf8.encode(jsonEncode(source)).length > 32768) {
    throw const FormatException('現在の会社設定を確認できません');
  }
  // Legacy source values are an opaque CAS snapshot. Never trim, default,
  // reinterpret units or normalize old names while editing only tax/welfare.
  CompanyCommonTaxRate.fromNumber(source['tax_rate']);
  CompanyCommonTaxRate.fromNumber(source['welfare_rate']);
  return _freeze(source) as Map<String, dynamic>;
}

/// Percentage values, not fractions: 10 means 10%. Exact four-place editing.
class CompanyCommonTaxRate {
  const CompanyCommonTaxRate._(this.scaled);
  final int scaled;
  factory CompanyCommonTaxRate.parse(String text) {
    final value = text.trim();
    if (!RegExp(r'^\d{1,3}(?:\.\d{1,4})?$').hasMatch(value)) {
      throw const FormatException('0〜100、小数4桁以内で入力してください');
    }
    final parts = value.split('.');
    final scaled = int.parse(parts[0]) * 10000 + int.parse(parts.length == 1 ? '0' : parts[1].padRight(4, '0'));
    if (scaled > 1000000) throw const FormatException('0〜100で入力してください');
    return CompanyCommonTaxRate._(scaled);
  }
  factory CompanyCommonTaxRate.fromNumber(Object? value) {
    if (value is! num || !value.isFinite) throw const FormatException('税率の数値を確認できません');
    return CompanyCommonTaxRate.parse(value.toString());
  }
  num get number => scaled % 10000 == 0 ? scaled ~/ 10000 : scaled / 10000;
  String get text {
    if (scaled % 10000 == 0) return '${scaled ~/ 10000}';
    return '${scaled ~/ 10000}.${(scaled % 10000).toString().padLeft(4, '0').replaceFirst(RegExp(r'0+$'), '')}';
  }
}

class CompanyCommonTaxState {
  const CompanyCommonTaxState._({required this.companyId, required this.canEdit,
    required this.version, required this.expectedSource, required this.taxRate, required this.welfareRate});
  final String companyId;
  final bool canEdit;
  final int version;
  final Map<String, dynamic> expectedSource;
  final CompanyCommonTaxRate taxRate;
  final CompanyCommonTaxRate welfareRate;
  factory CompanyCommonTaxState.parse(Object? raw, String companyId, {bool commit = false}) {
    final value = commonTaxObject(raw);
    final keys = {..._stateKeys, if (commit) ...['request_id', 'committed_version', 'id_map']};
    if (value.length != keys.length || !value.keys.every(keys.contains) || value['contract_version'] != 1 ||
        value['company_id'] is! String || commonTaxUuid(value['company_id']) != commonTaxUuid(companyId) ||
        value['can_edit'] is! bool || value['version'] is! int || value['version'] < 0 || value['version'] > 9007199254740991 ||
        value['legacy_refs'] is! List || (value['legacy_refs'] as List).length != 3 || value['items'] is! List ||
        (value['items'] as List).length > 300 || utf8.encode(jsonEncode(value)).length > 256 * 1024) {
      throw const FormatException('税率設定の応答を確認できません');
    }
    final source = _source(value['expected_source']);
    final tax = CompanyCommonTaxRate.fromNumber(value['tax_rate']);
    final welfare = CompanyCommonTaxRate.fromNumber(value['welfare_rate']);
    if (tax.scaled != CompanyCommonTaxRate.fromNumber(source['tax_rate']).scaled ||
        welfare.scaled != CompanyCommonTaxRate.fromNumber(source['welfare_rate']).scaled) {
      throw const FormatException('税率設定の現在値が一致しません');
    }
    return CompanyCommonTaxState._(companyId: commonTaxUuid(companyId), canEdit: value['can_edit'],
      version: value['version'], expectedSource: source, taxRate: tax, welfareRate: welfare);
  }
  bool sameSource(CompanyCommonTaxState other) => version == other.version && commonTaxEqual(expectedSource, other.expectedSource);
}

class CompanyCommonTaxRequest {
  CompanyCommonTaxRequest({required String companyId, required String actorId,
    required String requestId, required this.expectedVersion, required Map<String, dynamic> expectedSource,
    required this.taxRate, required this.welfareRate})
    : companyId = commonTaxUuid(companyId), actorId = commonTaxUuid(actorId), requestId = commonTaxUuid(requestId),
      expectedSource = _source(expectedSource) {
    if (expectedVersion < 0 || expectedVersion > 9007199254740990) throw const FormatException('設定の版を確認できません');
  }
  final String companyId;
  final String actorId;
  final String requestId;
  final int expectedVersion;
  final Map<String, dynamic> expectedSource;
  final CompanyCommonTaxRate taxRate;
  final CompanyCommonTaxRate welfareRate;
  Map<String, dynamic> get payload => {'operation': 'tax', 'expected_version': expectedVersion,
    'expected_source': expectedSource, 'tax_rate': taxRate.number, 'welfare_rate': welfareRate.number};
  Map<String, dynamic> toJson() => {'journal_version': 1, 'company_id': companyId, 'actor_id': actorId,
    'request_id': requestId, 'request_payload': payload};
  factory CompanyCommonTaxRequest.parse(Object? raw, String companyId, String actorId) {
    final value = commonTaxObject(raw);
    final keys = {'journal_version', 'company_id', 'actor_id', 'request_id', 'request_payload'};
    if (value.length != keys.length || !value.keys.every(keys.contains) || value['journal_version'] != 1 ||
        value['company_id'] != commonTaxUuid(companyId) || value['actor_id'] != commonTaxUuid(actorId) || value['request_id'] is! String) {
      throw const FormatException('保存確認情報の対象が違います');
    }
    final payload = commonTaxObject(value['request_payload']);
    if (payload.length != _payloadKeys.length || !payload.keys.every(_payloadKeys.contains) ||
        payload['operation'] != 'tax' || payload['expected_version'] is! int) {
      throw const FormatException('保存確認情報を確認できません');
    }
    return CompanyCommonTaxRequest(companyId: companyId, actorId: actorId, requestId: value['request_id'],
      expectedVersion: payload['expected_version'], expectedSource: commonTaxObject(payload['expected_source']),
      taxRate: CompanyCommonTaxRate.fromNumber(payload['tax_rate']), welfareRate: CompanyCommonTaxRate.fromNumber(payload['welfare_rate']));
  }
  CompanyCommonTaxState validateCommit(Object? raw) {
    final value = commonTaxObject(raw);
    final state = CompanyCommonTaxState.parse(value, companyId, commit: true);
    if (value['request_id'] != requestId || value['committed_version'] != expectedVersion + 1 ||
        state.version != expectedVersion + 1 || value['id_map'] is! List || (value['id_map'] as List).isNotEmpty ||
        state.taxRate.scaled != taxRate.scaled || state.welfareRate.scaled != welfareRate.scaled ||
        !commonTaxEqual(state.expectedSource['legacy_slots'], expectedSource['legacy_slots']) ||
        state.expectedSource['legacy_version'] != expectedSource['legacy_version'] ||
        state.expectedSource['legacy_adopted'] != expectedSource['legacy_adopted']) {
      throw const FormatException('保存結果の対象・金額を確認できません');
    }
    return state;
  }
  CompanyCommonTaxState? validateReceipt(Object? raw) {
    final value = commonTaxObject(raw);
    final base = {'contract_version', 'company_id', 'request_id', 'found'};
    if (value['contract_version'] != 1 || value['company_id'] != companyId || value['request_id'] != requestId || value['found'] is! bool) {
      throw const FormatException('保存確認応答の対象が違います');
    }
    if (value['found'] == false) {
      if (value.length != base.length || !value.keys.every(base.contains)) throw const FormatException('保存確認応答を確認できません');
      return null;
    }
    final keys = {...base, 'actor_id', 'operation', 'payroll_type', 'expected_version', 'request_payload', 'committed_version', 'result'};
    if (value.length != keys.length || !value.keys.every(keys.contains) || value['actor_id'] != actorId ||
        value['operation'] != 'tax' || value['payroll_type'] != null || value['expected_version'] != expectedVersion ||
        !commonTaxEqual(value['request_payload'], payload) || value['committed_version'] != expectedVersion + 1) {
      throw const FormatException('保存確認応答の操作が一致しません');
    }
    return validateCommit(value['result']);
  }
}

class CompanyCommonTaxUnavailable implements Exception { const CompanyCommonTaxUnavailable(); }
abstract class CompanyCommonTaxRepository {
  String? get actorId;
  Stream<String?> get actorChanges;
  Future<CompanyCommonTaxState> read(String companyId);
  Future<CompanyCommonTaxState> save(CompanyCommonTaxRequest request);
  Future<CompanyCommonTaxState?> receipt(CompanyCommonTaxRequest request);
}
class SupabaseCompanyCommonTaxRepository implements CompanyCommonTaxRepository {
  SupabaseCompanyCommonTaxRepository(this.client);
  final SupabaseClient client;
  static CompanyCommonTaxRepository? maybeCreate() => SupabaseBackend.isInitialized && SupabaseBackend.client.auth.currentUser != null
      ? SupabaseCompanyCommonTaxRepository(SupabaseBackend.client) : null;
  @override
  String? get actorId => client.auth.currentUser?.id;
  @override
  Stream<String?> get actorChanges => client.auth.onAuthStateChange.map((event) => event.session?.user.id);
  Future<dynamic> _call(String name, Map<String, dynamic> params, {String? expectedActor}) async {
    final session = client.auth.currentSession;
    if (session == null || (expectedActor != null && session.user.id != expectedActor)) throw StateError('ログイン状態が変わりました');
    try {
      final result = await client.rpc(name, params: params).setHeader('Authorization', 'Bearer ${session.accessToken}')
          .timeout(const Duration(seconds: 30));
      if (actorId != session.user.id) throw StateError('ログイン状態が変わりました');
      return result;
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST202') throw const CompanyCommonTaxUnavailable();
      rethrow;
    }
  }
  @override
  Future<CompanyCommonTaxState> read(String companyId) async => CompanyCommonTaxState.parse(
    await _call('read_company_common_allowances_admin', {'p_company_id': commonTaxUuid(companyId)}), companyId);
  @override
  Future<CompanyCommonTaxState> save(CompanyCommonTaxRequest request) async => request.validateCommit(
    await _call('save_company_common_tax_settings', {'p_company_id': request.companyId,
      'p_expected_version': request.expectedVersion, 'p_expected_source': request.expectedSource,
      'p_tax_rate': request.taxRate.number, 'p_welfare_rate': request.welfareRate.number,
      'p_request_id': request.requestId}, expectedActor: request.actorId));
  @override
  Future<CompanyCommonTaxState?> receipt(CompanyCommonTaxRequest request) async => request.validateReceipt(
    await _call('read_company_common_allowance_request', {'p_company_id': request.companyId,
      'p_request_id': request.requestId}, expectedActor: request.actorId));
}

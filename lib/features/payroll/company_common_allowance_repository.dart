import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/supabase_backend.dart';

const commonAllowanceTypes = ['daily', 'hourly', 'monthly'];
const _maxVersion = 9007199254740990;
bool _version(Object? value) => value is int && value >= 0 && value <= _maxVersion;
bool _uuid(Object? value) => value is String && RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(value);
Map<String, dynamic> _object(Object? raw) {
  if (raw is! Map) throw const FormatException('会社共通手当の応答を確認できません');
  return Map<String, dynamic>.from(raw);
}
dynamic _freeze(dynamic value) {
  if (value is Map) return Map<String, dynamic>.unmodifiable(value.map((key, entry) => MapEntry(key as String, _freeze(entry))));
  if (value is List) return List<dynamic>.unmodifiable(value.map(_freeze));
  return value;
}
bool commonAllowanceEqual(Object? a, Object? b) {
  if (a is Map && b is Map) return a.length == b.length && a.keys.every((key) => b.containsKey(key) && commonAllowanceEqual(a[key], b[key]));
  if (a is List && b is List) return a.length == b.length && List.generate(a.length, (i) => i).every((i) => commonAllowanceEqual(a[i], b[i]));
  return a == b;
}

class CompanyCommonAllowanceState {
  const CompanyCommonAllowanceState({required this.companyId, required this.version, required this.canEdit, required this.items, required this.legacyRefs, required this.expectedSource});
  final String companyId;
  final int version;
  final bool canEdit;
  final List<Map<String, dynamic>> items;
  final List<Map<String, dynamic>> legacyRefs;
  final Map<String, dynamic> expectedSource;
  factory CompanyCommonAllowanceState.parse(Object? raw, String companyId) {
    final value = _object(raw);
    if (value['contract_version'] != 1 || value['company_id'] != companyId || !_version(value['version']) || value['can_edit'] is! bool || value['items'] is! List || value['legacy_refs'] is! List) throw const FormatException('会社共通手当の形式を確認できません');
    final items = <Map<String, dynamic>>[];
    final ids = <String>{};
    final counts = <String, int>{};
    for (final rawItem in value['items'] as List) {
      final item = _object(rawItem);
      final type = item['payroll_type'];
      final amount = item['amount_yen'];
      if (!_uuid(item['id']) || !ids.add(item['id'] as String) || !commonAllowanceTypes.contains(type) || !['earning', 'deduction'].contains(item['section']) || !['hour', 'day', 'month'].contains(item['unit']) || item['name'] is! String || (item['name'] as String).trim().isEmpty || (item['name'] as String).length > 80 || amount is! int || amount < 0 || amount > 2147483647) throw const FormatException('会社共通手当の項目を確認できません');
      counts[type as String] = (counts[type] ?? 0) + 1;
      if (counts[type]! > 100) throw const FormatException('会社共通手当の件数が上限を超えています');
      items.add(Map.unmodifiable(item));
    }
    final legacy = (value['legacy_refs'] as List).map(_object).toList()..sort((a,b) => (a['slot'] as int).compareTo(b['slot'] as int));
    if (legacy.length != 3 || legacy.map((x) => x['slot']).toSet().length != 3 || legacy.any((x) => ![1, 2, 3].contains(x['slot']) || (x['name'] != null && x['name'] is! String) || x['source_unit'] is! String || x['amount_yen'] is! int || x['applicability'] != 'all' || x['section'] != 'earning' || x['unit'] != 'day' || x['id'] != null && !_uuid(x['id']) || x['generation'] != null && !_version(x['generation']))) throw const FormatException('旧手当の原値を確認できません');
    final source = _object(value['expected_source']);
    if (source['legacy_adopted'] is! bool || !_version(source['legacy_version']) || source['legacy_slots'] is! List || (source['legacy_slots'] as List).length != 3 || source['tax_rate'] is! num || source['welfare_rate'] is! num) throw const FormatException('設定元の版を確認できません');
    return CompanyCommonAllowanceState(companyId: companyId, version: value['version'] as int, canEdit: value['can_edit'] as bool, items: List.unmodifiable(items), legacyRefs: List.unmodifiable(legacy.map((x) => Map<String, dynamic>.unmodifiable(x))), expectedSource: Map.unmodifiable(source));
  }
}

class CompanyCommonAllowancePending {
  CompanyCommonAllowancePending({required this.actorId, required this.companyId, required this.payrollType, required this.expectedVersion, required this.requestId, required Map<String, dynamic> expectedSource, required List<Map<String, dynamic>> legacySlots, required this.confirmAdoption, required List<Map<String, dynamic>> items}) : items = List.unmodifiable(items.map((x) => Map<String, dynamic>.unmodifiable(x))), expectedSource = _freeze(expectedSource) as Map<String, dynamic>, legacySlots = List.unmodifiable(legacySlots.map((x) => Map<String, dynamic>.unmodifiable(x))) {
    if (actorId.isEmpty || companyId.isEmpty || !commonAllowanceTypes.contains(payrollType) || !_version(expectedVersion) || !_uuid(requestId) || items.length > 100 || utf8.encode(jsonEncode(items)).length > 131072) throw const FormatException('保存内容を確認できません');
    final keys = <String>{};
    if (legacySlots.length != 3 || legacySlots.map((x) => x['slot']).toSet().length != 3 || legacySlots.any((x) => x.length != 6 || !x.keys.toSet().containsAll({'slot','id','generation','name','source_unit','amount_yen'}) || ![1,2,3].contains(x['slot']) || x['id'] != null && !_uuid(x['id']) || x['generation'] != null && !_version(x['generation']) || x['name'] != null && (x['name'] is! String || (x['name'] as String).trim().isEmpty || (x['name'] as String).length > 80) || x['source_unit'] is! String || (x['source_unit'] as String).trim().isEmpty || (x['source_unit'] as String).length > 12 || x['amount_yen'] is! int || (x['amount_yen'] as int) < 0 || (x['amount_yen'] as int) > 2147483647)) throw const FormatException('既存手当の保存内容を確認できません');
    for (final item in items) {
      final amount = item['amount_yen'];
      if (item.length != 6 || !item.keys.toSet().containsAll({'id', 'client_key', 'section', 'unit', 'name', 'amount_yen'}) || (item['id'] != null && !_uuid(item['id'])) || item['client_key'] is! String || !RegExp(r'^[-_A-Za-z0-9]{1,120}$').hasMatch(item['client_key'] as String) || !keys.add(item['client_key'] as String) || !['earning', 'deduction'].contains(item['section']) || !['hour', 'day', 'month'].contains(item['unit']) || item['name'] is! String || (item['name'] as String).trim().isEmpty || (item['name'] as String).length > 80 || amount is! int || amount < 0 || amount > 2147483647) throw const FormatException('保存する手当の内容を確認できません');
    }
  }
  final String actorId, companyId, payrollType, requestId;
  final int expectedVersion;
  final List<Map<String, dynamic>> items;
  final Map<String, dynamic> expectedSource;
  final List<Map<String, dynamic>> legacySlots;
  final bool confirmAdoption;
  Map<String, dynamic> get payload => {'operation': 'allowances', 'payroll_type': payrollType, 'expected_version': expectedVersion, 'expected_source': expectedSource, 'items': items, 'legacy_slots': legacySlots, 'confirm_adoption': confirmAdoption};
  Map<String, dynamic> toJson() => {'actor_id': actorId, 'company_id': companyId, 'request_id': requestId, ...payload};
  factory CompanyCommonAllowancePending.parse(Object? raw) {
    final x = _object(raw);
    if (x['operation'] != 'allowances') throw const FormatException('保存確認記録の操作が一致しません');
    return CompanyCommonAllowancePending(actorId: x['actor_id'] as String, companyId: x['company_id'] as String, requestId: x['request_id'] as String, payrollType: x['payroll_type'] as String, expectedVersion: x['expected_version'] as int, expectedSource: _object(x['expected_source']), legacySlots: (x['legacy_slots'] as List).map(_object).toList(), confirmAdoption: x['confirm_adoption'] as bool, items: (x['items'] as List).map(_object).toList());
  }
}

abstract interface class CompanyCommonAllowanceRepository {
  String? get actorId;
  Stream<String?> get actorChanges;
  Future<CompanyCommonAllowanceState> read(String companyId);
  Future<CompanyCommonAllowanceState> save(CompanyCommonAllowancePending pending);
  Future<CompanyCommonAllowanceState?> reconcile(CompanyCommonAllowancePending pending);
}

class SupabaseCompanyCommonAllowanceRepository implements CompanyCommonAllowanceRepository {
  SupabaseCompanyCommonAllowanceRepository._(this._client) : _invoke = null, _actor = null, _actorChanges = null;
  SupabaseCompanyCommonAllowanceRepository.forTesting({required Future<dynamic> Function(String, Map<String, dynamic>) invoke, required String? Function() actor, Stream<String?>? actorChanges}) : _client = null, _invoke = invoke, _actor = actor, _actorChanges = actorChanges;
  final SupabaseClient? _client;
  final Future<dynamic> Function(String, Map<String, dynamic>)? _invoke;
  final String? Function()? _actor;
  final Stream<String?>? _actorChanges;
  static SupabaseCompanyCommonAllowanceRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized || SupabaseBackend.client.auth.currentUser == null) return null;
    return SupabaseCompanyCommonAllowanceRepository._(SupabaseBackend.client);
  }
  @override String? get actorId => _actor != null ? _actor() : _client?.auth.currentUser?.id;
  @override Stream<String?> get actorChanges => _actorChanges ?? _client?.auth.onAuthStateChange.map((event) => event.session?.user.id) ?? const Stream.empty();
  Future<dynamic> _call(String name, Map<String, dynamic> args, {String? expectedActor}) async {
    final actor = actorId;
    if (actor == null || (expectedActor != null && actor != expectedActor)) throw StateError('ログイン情報が変更されました');
    dynamic raw;
    if (_invoke != null) {
      raw = await _invoke(name, args);
    } else {
      final token = _client!.auth.currentSession?.accessToken;
      if (token == null) throw StateError('本人確認が必要です');
      raw = await _client.rpc(name, params: args).setHeader('Authorization', 'Bearer $token');
    }
    if (actorId != actor) throw StateError('ログイン情報が変更されました');
    return raw;
  }
  @override Future<CompanyCommonAllowanceState> read(String companyId) async => CompanyCommonAllowanceState.parse(await _call('read_company_common_allowances_admin', {'p_company_id': companyId}), companyId);
  CompanyCommonAllowanceState _result(Object? raw, CompanyCommonAllowancePending pending) {
    final x = _object(raw);
    if (x['request_id'] != pending.requestId || x['committed_version'] != pending.expectedVersion + 1) throw const FormatException('保存結果を確定できません');
    final state = CompanyCommonAllowanceState.parse(x, pending.companyId);
    if (state.version != x['committed_version'] || x['id_map'] is! List) throw const FormatException('保存結果の版を確認できません');
    final mappings = (x['id_map'] as List).map(_object).toList();
    final mapped = <String, String>{};
    for (final m in mappings) {
      if (m['client_key'] is! String || !_uuid(m['id']) || mapped.containsKey(m['client_key'])) throw const FormatException('保存した項目IDを確認できません');
      mapped[m['client_key'] as String] = m['id'] as String;
    }
    final saved = state.items.where((x) => x['payroll_type'] == pending.payrollType).toList();
    if (saved.length != pending.items.length || mapped.length != pending.items.length || mapped.values.toSet().length != mapped.length) throw const FormatException('保存した項目数を確認できません');
    for (final item in pending.items) {
      final id = mapped[item['client_key']];
      final match = saved.where((x) => x['id'] == id).toList();
      if (match.length != 1 || (item['id'] != null && item['id'] != id) || ['section', 'unit', 'name', 'amount_yen'].any((key) => match.single[key] != item[key])) throw const FormatException('保存内容と応答が一致しません');
    }
    for (final item in pending.legacySlots) {
      final saved = state.legacyRefs.singleWhere((x) => x['slot'] == item['slot']);
      if (saved['name'] != item['name'] || saved['amount_yen'] != item['amount_yen'] || saved['source_unit'] != item['source_unit'] || item['id'] != null && item['name'] != null && saved['id'] != item['id']) throw const FormatException('旧手当の保存結果が一致しません');
    }
    return state;
  }
  @override Future<CompanyCommonAllowanceState> save(CompanyCommonAllowancePending p) async => _result(await _call('save_company_common_allowances', {'p_company_id': p.companyId, 'p_payroll_type': p.payrollType, 'p_expected_version': p.expectedVersion, 'p_expected_source': p.expectedSource, 'p_request_id': p.requestId, 'p_items': p.items, 'p_legacy_slots': p.legacySlots, 'p_confirm_adoption': p.confirmAdoption}, expectedActor: p.actorId), p);
  @override Future<CompanyCommonAllowanceState?> reconcile(CompanyCommonAllowancePending p) async {
    final x = _object(await _call('read_company_common_allowance_request', {'p_company_id': p.companyId, 'p_request_id': p.requestId}, expectedActor: p.actorId));
    if (x['contract_version'] != 1 || x['company_id'] != p.companyId || x['request_id'] != p.requestId || x['found'] is! bool) throw const FormatException('保存状態を確認できません');
    if (x['found'] == false) return null;
    if (x['operation'] != 'allowances' || x['actor_id'] != p.actorId || x['payroll_type'] != p.payrollType || x['expected_version'] != p.expectedVersion || x['committed_version'] != p.expectedVersion + 1 || !commonAllowanceEqual(x['request_payload'], p.payload)) throw const FormatException('保存履歴が送信内容と一致しません');
    return _result(x['result'], p);
  }
}

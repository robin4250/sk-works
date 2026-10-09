import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/supabase_backend.dart';

Map<String, dynamic> allowanceIdentityObject(dynamic raw) {
  if (raw is! Map) {
    throw const FormatException('手当データを確認できません');
  }
  return Map<String, dynamic>.from(raw);
}

bool allowanceIdentityEqual(dynamic a, dynamic b) {
  if (a is Map && b is Map) {
    return a.length == b.length && a.keys.every((key) => b.containsKey(key) && allowanceIdentityEqual(a[key], b[key]));
  }
  if (a is List && b is List) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (!allowanceIdentityEqual(a[i], b[i])) {
        return false;
      }
    }
    return true;
  }
  return a == b;
}

class CompanyAllowanceSlot {
  const CompanyAllowanceSlot({required this.slot, required this.name, required this.unit, required this.amountYen});
  final int slot;
  final String? name;
  final String unit;
  final int amountYen;
  bool get active => name?.trim().isNotEmpty == true;
  Map<String, dynamic> toJson() => {'slot': slot, 'name': name, 'unit': unit, 'amount_yen': amountYen};
  factory CompanyAllowanceSlot.parse(dynamic raw) {
    final value = allowanceIdentityObject(raw);
    if (value['slot'] is! int || (value['slot'] as int) < 1 || (value['slot'] as int) > 3 ||
        (value['name'] != null && value['name'] is! String) || value['unit'] is! String ||
        value['amount_yen'] is! int || (value['amount_yen'] as int) < 0) {
      throw const FormatException('会社手当の現在値を確認できません');
    }
    return CompanyAllowanceSlot(slot: value['slot'] as int, name: value['name'] as String?,
      unit: value['unit'] as String, amountYen: value['amount_yen'] as int);
  }
}

class CompanyAllowanceIdentityData {
  const CompanyAllowanceIdentityData({required this.companyId, required this.version, required this.adopted,
    required this.slots, required this.items, required this.history, this.historyBeforeVersion});
  final String companyId;
  final int version;
  final bool adopted;
  final List<CompanyAllowanceSlot> slots;
  final List<Map<String, dynamic>> items;
  final List<Map<String, dynamic>> history;
  final int? historyBeforeVersion;
  factory CompanyAllowanceIdentityData.parse(dynamic raw, String companyId) {
    final value = allowanceIdentityObject(raw);
    if (value['contract_version'] != 1 || value['company_id'] != companyId || value['version'] is! int ||
        (value['version'] as int) < 0 || value['adopted'] is! bool || value['observed_slots'] is! List ||
        value['items'] is! List || value['history'] is! List ||
        (value['history_before_version'] != null && value['history_before_version'] is! int)) {
      throw const FormatException('会社手当の保存状態を確認できません');
    }
    final slots = (value['observed_slots'] as List).map(CompanyAllowanceSlot.parse).toList();
    final adopted = value['adopted'] == true;
    if (slots.length != 3 || slots.map((s) => s.slot).toSet().length != 3 ||
        (adopted ? value['version'] < 1 : value['version'] != 0)) {
      throw const FormatException('会社手当の版を確認できません');
    }
    final items = (value['items'] as List).map(allowanceIdentityObject).toList();
    final ids = <String>{};
    final activeSlots = <int>{};
    for (final item in items) {
      final slot = CompanyAllowanceSlot.parse(item);
      if (!adopted || !slot.active || item['id'] is! String ||
          !RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(item['id'] as String) ||
          item['generation'] is! int || item['generation'] < 1 || !ids.add(item['id'] as String) ||
          !activeSlots.add(slot.slot) || !allowanceIdentityEqual(slot.toJson(), slots.firstWhere((s) => s.slot == slot.slot).toJson())) {
        throw const FormatException('会社手当のIDを確認できません');
      }
    }
    if (adopted && activeSlots.length != slots.where((s) => s.active).length) {
      throw const FormatException('会社手当のIDが不足しています');
    }
    final history = (value['history'] as List).map(allowanceIdentityObject).toList();
    if (history.length > 100) {
      throw const FormatException('手当履歴の取得範囲を確認できません');
    }
    for (final entry in history) {
      validateAllowanceHistory(entry, companyId);
    }
    return CompanyAllowanceIdentityData(companyId: companyId, version: value['version'] as int,
      adopted: adopted, slots: slots, items: items, history: history,
      historyBeforeVersion: value['history_before_version'] as int?);
  }
}

void validateAllowanceHistory(Map<String, dynamic> row, String companyId) {
  if (row['company_id'] != companyId || row['version'] is! int || row['version'] < 1 ||
      row['actor_id'] is! String || row['changed_at'] is! String || DateTime.tryParse(row['changed_at'] as String) == null ||
      !['adopt', 'settings_update'].contains(row['event']) || row['after_value'] is! List) {
    throw const FormatException('手当履歴を確認できません');
  }
  for (final item in row['after_value'] as List) {
    final value = allowanceIdentityObject(item);
    CompanyAllowanceSlot.parse(value);
    if (value['id'] is! String || value['generation'] is! int || value['generation'] < 1) {
      throw const FormatException('手当履歴のIDを確認できません');
    }
  }
}

class CompanyAllowanceHistoryPage {
  const CompanyAllowanceHistoryPage(this.entries, this.beforeVersion);
  final List<Map<String, dynamic>> entries;
  final int? beforeVersion;
}

class CompanyAllowanceIdentityUnavailable implements Exception {
  const CompanyAllowanceIdentityUnavailable();
}

typedef CompanyAllowanceIdentityRpc = Future<dynamic> Function(String name, Map<String, dynamic> params);
abstract class CompanyAllowanceIdentityRepository {
  Future<CompanyAllowanceIdentityData> read(String companyId);
  Future<CompanyAllowanceIdentityData> adopt(String companyId, List<CompanyAllowanceSlot> observed);
  Future<CompanyAllowanceIdentityData> save(String companyId, int version, CompanyAllowanceSlot slot);
  Future<CompanyAllowanceHistoryPage> history(String companyId, {int? beforeVersion, int limit = 50});
}

class SupabaseCompanyAllowanceIdentityRepository implements CompanyAllowanceIdentityRepository {
  SupabaseCompanyAllowanceIdentityRepository({CompanyAllowanceIdentityRpc? invoke}) : _invoke = invoke;
  final CompanyAllowanceIdentityRpc? _invoke;
  Future<dynamic> _call(String name, Map<String, dynamic> params) async {
    return _invoke != null ? _invoke(name, params) : SupabaseBackend.client.rpc(name, params: params);
  }
  @override
  Future<CompanyAllowanceIdentityData> read(String companyId) async {
    try {
      return CompanyAllowanceIdentityData.parse(await _call('read_company_allowance_identity_admin', {'p_company_id': companyId}), companyId);
    } on PostgrestException catch (error) {
      if ((error.code == 'PGRST202' || error.code == '42883') && error.message.contains('read_company_allowance_identity_admin')) {
        throw const CompanyAllowanceIdentityUnavailable();
      }
      rethrow;
    }
  }
  @override
  Future<CompanyAllowanceIdentityData> adopt(String companyId, List<CompanyAllowanceSlot> observed) async {
    return CompanyAllowanceIdentityData.parse(await _call('adopt_company_allowance_identity', {
      'p_company_id': companyId, 'p_observed_slots': observed.map((s) => s.toJson()).toList(), 'p_confirmed': true}), companyId);
  }
  @override
  Future<CompanyAllowanceIdentityData> save(String companyId, int version, CompanyAllowanceSlot slot) async {
    return CompanyAllowanceIdentityData.parse(await _call('save_company_allowance_identity_slot', {
      'p_company_id': companyId, 'p_slot': slot.slot, 'p_expected_version': version, 'p_name': slot.name,
      'p_unit': slot.unit, 'p_amount_yen': slot.amountYen, 'p_confirmed': true}), companyId);
  }
  @override
  Future<CompanyAllowanceHistoryPage> history(String companyId, {int? beforeVersion, int limit = 50}) async {
    final value = allowanceIdentityObject(await _call('read_company_allowance_identity_history', {
      'p_company_id': companyId, 'p_before_version': beforeVersion, 'p_limit': limit}));
    if (value['contract_version'] != 1 || value['company_id'] != companyId || value['entries'] is! List ||
        (value['before_version'] != null && value['before_version'] is! int)) {
      throw const FormatException('手当履歴の保存状態を確認できません');
    }
    final entries = (value['entries'] as List).map(allowanceIdentityObject).toList();
    if (entries.length > limit || limit < 1 || limit > 100) {
      throw const FormatException('手当履歴の範囲を確認できません');
    }
    for (final entry in entries) {
      validateAllowanceHistory(entry, companyId);
      if (beforeVersion != null && entry['version'] >= beforeVersion) {
        throw const FormatException('手当履歴の版が違います');
      }
    }
    return CompanyAllowanceHistoryPage(entries, value['before_version'] as int?);
  }
}

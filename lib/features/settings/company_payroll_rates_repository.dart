import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

const companyPayrollScopePrefectures = <String>['北海道', '青森県', '岩手県', '宮城県', '秋田県', '山形県', '福島県', '茨城県', '栃木県', '群馬県', '埼玉県', '千葉県', '東京都', '神奈川県', '新潟県', '富山県', '石川県', '福井県', '山梨県', '長野県', '岐阜県', '静岡県', '愛知県', '三重県', '滋賀県', '京都府', '大阪府', '兵庫県', '奈良県', '和歌山県', '鳥取県', '島根県', '岡山県', '広島県', '山口県', '徳島県', '香川県', '愛媛県', '高知県', '福岡県', '佐賀県', '長崎県', '熊本県', '大分県', '宮崎県', '鹿児島県', '沖縄県'];

/// Percentage points in millionths: 1% = 1000000. No floating point conversion.
int parsePayrollRatePercent(String text) {
  final match = RegExp(r'^(\d{1,3})(?:\.(\d{1,6}))?$').firstMatch(text.trim());
  if (match == null) throw const FormatException('料率は小数点以下6桁までの数値で入力してください');
  final value = int.parse(match.group(1)!) * 1000000 +
      int.parse((match.group(2) ?? '').padRight(6, '0'));
  if (value > 100000000) throw const FormatException('料率は0〜100%で入力してください');
  return value;
}

String formatPayrollRatePercent(int value) {
  final fraction = (value % 1000000).toString().padLeft(6, '0').replaceFirst(RegExp(r'0+$'), '');
  return '${value ~/ 1000000}${fraction.isEmpty ? '' : '.$fraction'}';
}

Map<String, dynamic> payrollRateObject(dynamic raw) {
  if (raw is! Map) throw const FormatException('料率データの形式を確認できません');
  return Map<String, dynamic>.from(raw);
}

class CompanyPayrollRateItem {
  const CompanyPayrollRateItem({required this.id, required this.version, required this.value, required this.origin});
  final String id;
  final int version;
  final Map<String, dynamic> value;
  final String origin;
  factory CompanyPayrollRateItem.fromJson(dynamic raw) {
    final json = payrollRateObject(raw);
    if (json['item_id'] is! String || json['version'] is! int || json['origin'] is! String) {
      throw const FormatException('現在設定値の形式を確認できません');
    }
    return CompanyPayrollRateItem(id: json['item_id'] as String,
        version: json['version'] as int, value: validatePayrollRateValue(json['value']), origin: json['origin'] as String);
  }
}

Map<String, dynamic> validatePayrollRateValue(dynamic raw) {
  final value = payrollRateObject(raw);
  for (final key in ['kind', 'label', 'insurance_month', 'payroll_month', 'payment_month']) {
    if (value[key] is! String || (value[key] as String).isEmpty) {
      throw const FormatException('料率・適用年月のデータを確認できません');
    }
  }
  for (final key in ['insurance_month', 'payroll_month', 'payment_month']) {
    if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])-01$').hasMatch(value[key] as String)) {
      throw const FormatException('適用年月の形式を確認できません');
    }
  }
  for (final key in ['total', 'employee', 'employer']) {
    if (value[key] is! int || (value[key] as int) < 0 || (value[key] as int) > 100000000) {
      throw const FormatException('料率の数値を確認できません');
    }
  }
  if (value['total'] != (value['employee'] as int) + (value['employer'] as int)) {
    throw const FormatException('全体料率と負担率の合計が一致しません');
  }
  if (!['health_insurance', 'nursing_insurance', 'pension_insurance', 'employment_insurance', 'child_support', 'custom'].contains(value['kind'])) {
    throw const FormatException('料率項目の形式を確認できません');
  }
  final source = payrollRateObject(value['source']);
  for (final key in ['url', 'publisher', 'document_hash']) {
    if (source[key] is! String || (source[key] as String).trim().isEmpty) {
      throw const FormatException('情報元を確認できません');
    }
  }
  final sourceUri = Uri.tryParse(source['url'] as String);
  if (sourceUri == null || sourceUri.scheme != 'https' || sourceUri.host.isEmpty) throw const FormatException('情報元URLを確認できません');
  source['applicability'] = payrollRateObject(source['applicability']);
  if ((source['applicability'] as Map).values.any((value) => value is! String || value.trim().isEmpty)) {
    throw const FormatException('適用条件の形式を確認できません');
  }
  if ((source['applicability'] as Map).isEmpty) throw const FormatException('適用条件を確認できません');
  value['source'] = source;
  return value;
}

class CompanyPayrollRateCandidate {
  const CompanyPayrollRateCandidate({required this.id, required this.itemId, required this.value, required this.checkedAt, required this.scopeVersion});
  final String id;
  final String itemId;
  final Map<String, dynamic> value;
  final String checkedAt;
  final int scopeVersion;
  factory CompanyPayrollRateCandidate.fromJson(dynamic raw) {
    final json = payrollRateObject(raw);
    if (json['candidate_id'] is! String || json['item_id'] is! String || json['checked_at'] is! String || json['scope_version'] is! int || (json['scope_version'] as int) < 1) {
      throw const FormatException('確認値の形式を確認できません');
    }
    return CompanyPayrollRateCandidate(id: json['candidate_id'] as String,
      itemId: json['item_id'] as String, value: validatePayrollRateValue(json['value']), checkedAt: json['checked_at'] as String, scopeVersion: json['scope_version'] as int);
  }
}

class CompanyPayrollRateScope {
  const CompanyPayrollRateScope({required this.version, required this.value, required this.updatedBy, required this.updatedAt});
  final int version;
  final Map<String, dynamic> value;
  final String? updatedBy;
  final String updatedAt;
  factory CompanyPayrollRateScope.fromJson(dynamic raw) {
    final json = payrollRateObject(raw);
    final value = payrollRateObject(json['value']);
    if (json['version'] is! int || (json['version'] as int) < 1 || (json['updated_by'] != null && json['updated_by'] is! String) || json['updated_at'] is! String ||
        !['kyokai', 'union', 'other', 'unconfigured'].contains(value['insurer']) ||
        (value['prefecture'] != null && !companyPayrollScopePrefectures.contains(value['prefecture'])) ||
        (value['employment_business'] != null && !['general', 'agriculture_forestry_fisheries_sake', 'construction'].contains(value['employment_business']))) {
      throw const FormatException('会社の適用条件を確認できません');
    }
    return CompanyPayrollRateScope(version: json['version'] as int, value: value,
      updatedBy: json['updated_by'] as String?, updatedAt: json['updated_at'] as String);
  }
}

class CompanyPayrollRatesData {
  const CompanyPayrollRatesData({required this.items, required this.candidates, required this.history, this.companyScope, this.scopeHistory = const [], this.canEdit = false});
  final bool canEdit;
  final List<CompanyPayrollRateItem> items;
  final List<CompanyPayrollRateCandidate> candidates;
  final List<Map<String, dynamic>> history;
  final CompanyPayrollRateScope? companyScope;
  final List<Map<String, dynamic>> scopeHistory;
  factory CompanyPayrollRatesData.fromJson(dynamic raw) {
    final json = payrollRateObject(raw);
    if (json['items'] is! List || json['candidates'] is! List || json['history'] is! List || json['scope_history'] is! List || !json.containsKey('company_scope')) {
      throw const FormatException('料率設定を取得できませんでした');
    }
    return CompanyPayrollRatesData(
      canEdit: json['can_edit'] == true,
      items: (json['items'] as List).map(CompanyPayrollRateItem.fromJson).toList(),
      candidates: (json['candidates'] as List).map(CompanyPayrollRateCandidate.fromJson).toList(),
      history: (json['history'] as List).map(payrollRateObject).toList(),
      companyScope: json['company_scope'] == null ? null : CompanyPayrollRateScope.fromJson(json['company_scope']),
      scopeHistory: (json['scope_history'] as List).map(payrollRateObject).toList(),
    );
  }
}

abstract class CompanyPayrollRatesRepository {
  Future<CompanyPayrollRatesData> read(String companyId);
  Future<void> saveScope({required String companyId, required int expectedVersion, required Map<String, dynamic> value});
  Future<void> saveManual({required String companyId, required String itemId,
    required int expectedVersion, required Map<String, dynamic> value});
  Future<void> applyCandidate({required String companyId, required String itemId,
    required String candidateId, required int expectedVersion});
}

bool payrollRateValuesEqual(dynamic left, dynamic right) {
  if (left is Map && right is Map) {
    return left.length == right.length && left.keys.every((key) => right.containsKey(key) && payrollRateValuesEqual(left[key], right[key]));
  }
  if (left is List && right is List) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (!payrollRateValuesEqual(left[index], right[index])) return false;
    }
    return true;
  }
  return left == right;
}

typedef CompanyPayrollRateRpc = Future<dynamic> Function(String name, Map<String, dynamic> parameters);

class PayrollRatesUnavailable implements Exception {
  const PayrollRatesUnavailable();
}

/// A sent mutation remains unresolved until its exact committed value is read.
class PayrollRatePendingWrite {
  const PayrollRatePendingWrite({required this.companyId, required this.expectedVersion,
    required this.value, this.itemId, this.origin});
  final String companyId;
  final int expectedVersion;
  final Map<String, dynamic> value;
  final String? itemId;
  final String? origin;

  bool matches(CompanyPayrollRatesData data) {
    if (itemId == null) {
      final scope = data.companyScope;
      return scope != null && scope.version == expectedVersion + 1 &&
          payrollRateValuesEqual(scope.value, value);
    }
    for (final item in data.items) {
      if (item.id == itemId && item.version == expectedVersion + 1 && item.origin == origin &&
          payrollRateValuesEqual(item.value, value)) return true;
    }
    return false;
  }
}

class SupabaseCompanyPayrollRatesRepository implements CompanyPayrollRatesRepository {
  SupabaseCompanyPayrollRatesRepository({CompanyPayrollRateRpc? invoke}) : _invoke = invoke;
  final CompanyPayrollRateRpc? _invoke;
  Future<dynamic> _call(String name, Map<String, dynamic> parameters) async {
    final invoke = _invoke;
    if (invoke != null) return invoke(name, parameters);
    return SupabaseBackend.client.rpc(name, params: parameters);
  }

  void _verifySaved(dynamic raw, String itemId, int expectedVersion, String origin,
      {Map<String, dynamic>? requestedValue}) {
    final item = CompanyPayrollRateItem.fromJson(raw);
    if (item.id != itemId || item.version != expectedVersion + 1 || item.origin != origin ||
        (requestedValue != null && !payrollRateValuesEqual(item.value, requestedValue))) {
      throw const FormatException('保存結果を確認できません。再読み込みして確認してください');
    }
  }

  @override
  Future<CompanyPayrollRatesData> read(String companyId) async {
    try {
      final raw = await _call('read_company_payroll_rates', {'p_company_id': companyId});
      return CompanyPayrollRatesData.fromJson(raw);
    } on PostgrestException catch (error) {
      if ((error.code == 'PGRST202' || error.code == '42883') &&
          error.message.contains('read_company_payroll_rates')) {
        throw const PayrollRatesUnavailable();
      }
      rethrow;
    }
  }

  @override
  Future<void> saveScope({required String companyId, required int expectedVersion, required Map<String, dynamic> value}) async {
    final raw = await _call('save_company_payroll_rate_scope', {
      'p_company_id': companyId, 'p_expected_version': expectedVersion, 'p_value': value, 'p_confirmed': true,
    });
    final scope = CompanyPayrollRateScope.fromJson(raw);
    if (scope.version != expectedVersion + 1 || !payrollRateValuesEqual(scope.value, value)) {
      throw const FormatException('保存結果を確認できません。再読み込みして確認してください');
    }
  }

  @override
  Future<void> saveManual({required String companyId, required String itemId,
    required int expectedVersion, required Map<String, dynamic> value}) async {
    final raw = await _call('save_manual_company_payroll_rate', {
      'p_company_id': companyId, 'p_item_id': itemId, 'p_expected_version': expectedVersion,
      'p_value': value, 'p_confirmed': true,
    });
    _verifySaved(raw, itemId, expectedVersion, 'manual', requestedValue: value);
  }

  @override
  Future<void> applyCandidate({required String companyId, required String itemId,
    required String candidateId, required int expectedVersion}) async {
    final raw = await _call('apply_company_payroll_rate_candidate', {
      'p_company_id': companyId, 'p_item_id': itemId, 'p_candidate_id': candidateId,
      'p_expected_version': expectedVersion, 'p_confirmed': true,
    });
    _verifySaved(raw, itemId, expectedVersion, 'official_candidate');
  }
}

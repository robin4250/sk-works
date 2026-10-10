import 'dart:convert';

/// Compares only proposals actually shared by each company, never private site
/// registrations or a confirmation mistaken for a second company's proposal.
class SitePaymentTermsComparison {
  SitePaymentTermsComparison({required this.parent, required this.child});

  factory SitePaymentTermsComparison.fromWorkspace(Map<String, dynamic> workspace) {
    Map<String, dynamic>? latestFor(String companyKey) {
      final company = workspace[companyKey];
      if (company == null) return null;
      Map<String, dynamic>? latest;
      for (final value in workspace['proposals'] is List
          ? workspace['proposals'] as List : const []) {
        if (value is! Map || value['proposed_company_id'] != company ||
            value['revision'] is! num || value['terms'] is! Map) {
          continue;
        }
        if (latest == null || (value['revision'] as num) > (latest['revision'] as num)) {
          latest = Map<String, dynamic>.from(value);
        }
      }
      return latest;
    }
    return SitePaymentTermsComparison(
      parent: latestFor('parent_company_id'), child: latestFor('child_company_id'));
  }

  final Map<String, dynamic>? parent;
  final Map<String, dynamic>? child;
  bool get bothShared => parent != null && child != null;

  static const fields = <String, String>{
    'mode': '計算方式',
    'period_start': '対象期間 開始',
    'period_end': '対象期間 終了',
    'base_amount_yen': '基本額（円）',
    'unit_price_yen': '平米単価（円）',
    'area': '平米数',
    'adjustments': '追加項目・福利厚生費',
    'tax_included': '税込／税別',
    'taxable_amount_yen': '課税対象額（円）',
    'tax_rate': '税率（%）',
    'tax_amount_yen': '消費税額（円）',
    'rounding_rule': '端数処理',
    'tax_override_reason': '税額の手動変更理由',
    'final_amount_yen': '最終額（円）',
  };

  dynamic _value(Map<String, dynamic>? proposal, String field) =>
      proposal == null ? null : (proposal['terms'] as Map)[field];

  Object? _canonical(dynamic value) {
    if (value is num) return value.isFinite && value == value.roundToDouble() ? value.toInt() : value;
    if (value is String) return value;
    if (value is List) {
      final items = value.map((item) => jsonEncode(_canonical(item))).toList()..sort();
      return jsonEncode(items);
    }
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return {for (final key in keys) key: _canonical(value[key])};
    }
    return value;
  }

  bool differs(String field) => bothShared &&
      jsonEncode(_canonical(_value(parent, field))) !=
      jsonEncode(_canonical(_value(child, field)));

  String display(Map<String, dynamic>? proposal, String field) {
    if (proposal == null) return '未共有';
    final value = _value(proposal, field);
    if (value == null) return '未設定';
    if (field == 'mode') return value == 'square_meter' ? '平米計算' : value == 'lump_sum' ? '請け負い' : value.toString();
    if (field == 'tax_included') return value == true ? '税込（税額を加算しない）' : '税別';
    if (field == 'rounding_rule') return {'floor': '切り捨て', 'nearest': '四捨五入', 'ceil': '切り上げ'}[value] ?? value.toString();
    if (field == 'adjustments' && value is List) {
      if (value.isEmpty) return 'なし';
      return value.map((item) => item is Map
          ? '${item['name']}：${item['direction'] == 'deduction' ? '控除' : '加算'} ${item['amount_yen']}円'
          : '内容を確認してください').join('\n');
    }
    return value.toString().isEmpty ? '未設定' : value.toString();
  }
}

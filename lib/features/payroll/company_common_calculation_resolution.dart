import 'dart:convert';

/// Optional authorized projection from company_common.resolution. It carries
/// confirmation reasons, never raw settings or an alternate salary reader.
class CompanyCommonCalculationResolution {
  CompanyCommonCalculationResolution._(this.blocked, this.reasons);
  final bool blocked;
  final List<Map<String, dynamic>> reasons;
  factory CompanyCommonCalculationResolution.parse(Object? raw) {
    if (raw is! Map || raw['blocked'] is! bool ||
        (raw['reasons'] != null && raw['reasons'] is! List) ||
        (raw['selection_classification'] != null && raw['selection_classification'] is! List)) {
      throw StateError('Company common resolution unavailable');
    }
    final values = raw['reasons'] as List? ?? const [];
    if (values.length > 100 || utf8.encode(jsonEncode(raw)).length > 262144) {
      throw StateError('Company common resolution exceeds the supported bound');
    }
    final reasons = <Map<String, dynamic>>[];
    for (final value in values) {
      if (value is! Map || value['code'] is! String ||
          (value['code'] as String).isEmpty || (value['code'] as String).length > 80 ||
          value['name'] != null && (value['name'] is! String || (value['name'] as String).length > 160)) {
        throw StateError('Company common resolution reason unavailable');
      }
      // Deliberately project only presentation fields, not arbitrary server data.
      reasons.add(Map<String, dynamic>.unmodifiable({
        'code': value['code'], if (value['name'] != null) 'name': value['name'],
      }));
    }
    if (raw['blocked'] == false && reasons.isNotEmpty) {
      throw StateError('Company common resolution state differs');
    }
    return CompanyCommonCalculationResolution._(raw['blocked'] as bool, List.unmodifiable(reasons));
  }
  static String reasonLabel(Map<String, dynamic> reason, {String Function(String)? translate}) {
    final label = switch (reason['code']) {
      'worker_scope_missing' => '個別給料設定を確認してください',
      'publication_source_collision' => '共通手当の登録内容が重複しています',
      'attendance_interpretation_unconfirmed' => '日報の手当名を確認してください',
      'attendance_source_collision' => '同じ手当名の参照先を確認してください',
      'legacy_contract_unconfirmed' => '手当の日数計算方法を確認してください',
      'ambiguous_individual_name' => '個別設定に同じ手当名が重複しています',
      'individual_override_unresolved' => '会社共通と個別設定の単価が異なります',
      'individual_item_overlap_unresolved' => '会社共通と個別の追加手当が重複しています',
      _ => '共通手当の設定内容を確認してください',
    };
    final translated = translate?.call(label) ?? label;
    final name = reason['name'] as String?;
    return name == null || name.isEmpty ? translated : '$name：$translated';
  }
}

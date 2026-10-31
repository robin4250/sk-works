import '../../domain/trade_document_form_draft.dart';

/// Unbound user input held only in RAM. No company, person, seal or consent IDs
/// are fabricated before a registered counterparty has been selected.
class SiteOrderOutgoingEntries {
  SiteOrderOutgoingEntries(Map<String, String> input)
    : _input = Map.unmodifiable(input);
  final Map<String, String> _input;
  static const labels = {
    'work_name': '工事名称',
    'work_address': '工事場所',
    'period_start': '工期開始日',
    'period_end': '工期終了日',
    'unit_price': '単価（円）',
    'quantity': '数量',
    'unit': '単位',
    'total_amount_yen': '発注金額（円）',
    'tax_amount_yen': '消費税額（円）',
  };
  String value(String key) => _input[key] ?? '';
  int _money(String key) {
    final text = value(key).trim();
    if (!RegExp(r'^\d{1,10}$').hasMatch(text)) {
      throw const FormatException('金額を入力してください。');
    }
    final n = int.parse(text);
    if (n > 2147483647) throw const FormatException('金額の上限を超えています。');
    return n;
  }

  void validate() {
    if (_input.keys.any((k) => !labels.containsKey(k))) {
      throw const FormatException('入力項目を確認してください。');
    }
    for (final key in ['work_name', 'work_address']) {
      if (value(key).trim().isEmpty || value(key).runes.length > 240) {
        throw const FormatException('工事名称・場所を入力してください。');
      }
    }
    for (final key in ['period_start', 'period_end']) {
      final text = value(key), date = DateTime.tryParse(text);
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text) ||
          date == null ||
          date.toIso8601String().substring(0, 10) != text) {
        throw const FormatException('工期はYYYY-MM-DDで入力してください。');
      }
    }
    if (value('period_start').compareTo(value('period_end')) > 0) {
      throw const FormatException('工期を確認してください。');
    }
    _money('unit_price');
    final total = _money('total_amount_yen'), tax = _money('tax_amount_yen');
    if (tax > total) throw const FormatException('消費税額が発注金額を超えています。');
    if (value('quantity').length > 16 ||
        !RegExp(r'^\d+(?:\.\d{1,3})?$').hasMatch(value('quantity')) ||
        value('unit').trim().isEmpty ||
        value('unit').runes.length > 16) {
      throw const FormatException('数量・単位を確認してください。');
    }
  }

  String get unitPriceLabel {
    validate();
    return '${_money('unit_price')}円／${value('unit')}';
  }

  TradeDocumentFormDraft applyTo(TradeDocumentFormDraft boundDraft) {
    validate();
    final fields = TradeDocumentFormFields.fromJson(
      boundDraft.payload['form_fields'],
    ).toJson();
    final rows = fields['rows'] as List;
    rows[0] = {
      ...rows[0] as Map,
      'quantity': value('quantity'),
      'unit': value('unit'),
      'unit_price_yen': _money('unit_price'),
    };
    return boundDraft.withChanges({
      for (final key in [
        'work_name',
        'work_address',
        'period_start',
        'period_end',
      ])
        key: value(key),
      'total_amount_yen': _money('total_amount_yen'),
      'tax_amount_yen': _money('tax_amount_yen'),
      'form_fields': fields,
    });
  }
}

class SiteOrderRegisteredTarget {
  const SiteOrderRegisteredTarget({required this.id, required this.name});
  final String id, name;
}

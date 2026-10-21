import 'trade_document_attachment.dart';

/// Builds only an ephemeral PDF payload; never a financial/source record.
TradeDocumentAttachment standaloneTradeDocument({required Map<String, dynamic> context,
    required Map<String, String> fields}) {
  final acceptance = context['acceptance'] == true;
  String requiredText(String key, int max) {
    final value = fields[key]?.trim() ?? '';
    if (value.isEmpty || value.runes.length > max) throw StateError('必須項目・文字数を確認してください。');
    return value;
  }
  String date(String key) {
    final value = requiredText(key, 10);
    final parsed = DateTime.tryParse(value);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) || parsed == null ||
        parsed.toIso8601String().substring(0, 10) != value) throw StateError('日付はYYYY-MM-DDで入力してください。');
    return value;
  }
  final issue = date('issue_date');
  final order = date('order_date');
  final payload = <String, dynamic>{'version': 1, 'kind': acceptance ? 'acceptance' : 'order',
    'month': issue.substring(0, 7), 'issue_date': issue, 'order_date': order,
    'work_name': requiredText('work_name', 240), 'work_address': requiredText('work_address', 240),
    'company_seal_snapshot': context['company_seal_snapshot'], 'company_seal_enabled': context['company_seal_enabled'] == true};
  for (final party in ['issuer', 'counterparty']) {
    final original = Map<String, dynamic>.from(context[party] as Map);
    if ((original['name'] as String? ?? '').trim().isEmpty) throw StateError('会社名を登録してください。');
    final values = <String, dynamic>{'name': original['name']};
    for (final key in ['address', 'corporate_number', 'representative_name']) {
      final value = fields['$party.$key']?.trim() ?? original[key]?.toString().trim() ?? '';
      if (value.runes.length > (key == 'address' ? 240 : key == 'representative_name' ? 80 : 13) ||
          (key == 'corporate_number' && value.isNotEmpty && !RegExp(r'^[0-9]{13}$').hasMatch(value))) {
        throw StateError('会社情報の文字数・法人番号を確認してください。');
      }
      if (key != 'corporate_number' && value.isEmpty) throw StateError('住所・代表者名の不足情報を入力してください。');
      values[key] = value;
    }
    payload[party] = values;
  }
  for (final key in ['intro_text', 'payment_conditions', 'notes', 'acceptance_text']) {
    final value = fields[key]?.trim() ?? '';
    if (value.runes.length > (key == 'notes' ? 600 : 400)) throw StateError('文面の文字数を確認してください。');
    payload[key] = value.replaceAll('{order_date}', order);
  }
  if (!acceptance) {
    payload['period_start'] = date('period_start'); payload['period_end'] = date('period_end');
    if ((payload['period_start'] as String).compareTo(payload['period_end'] as String) > 0) throw StateError('工期を確認してください。');
    for (final key in ['total_amount_yen', 'tax_amount_yen']) {
      final input = requiredText(key, 12);
      if (!RegExp(r'^\d+$').hasMatch(input)) throw StateError('請負代金・消費税額を整数で入力してください。');
      final value = int.parse(input);
      if (value > 2147483647) throw StateError('金額が帳票の上限を超えています。');
      payload[key] = value;
    }
    if ((payload['tax_amount_yen'] as int) > (payload['total_amount_yen'] as int)) throw StateError('消費税額が請負代金を超えています。');
  }
  return TradeDocumentAttachment.fromJson({'version': 1, 'payload': payload});
}

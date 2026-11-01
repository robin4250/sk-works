import '../../domain/trade_document_form_draft.dart';

/// Closed input-error vocabulary; never displays exception message/source text.
enum StandaloneTradeDateError {
  orderIssueDate,
  acceptanceIssueDate,
  orderDate,
  periodStart,
  periodEnd,
}

class StandaloneTradeDateException implements Exception {
  const StandaloneTradeDateException(this.field);
  final StandaloneTradeDateError field;
}

void validateStandaloneTradeDocumentDraft(TradeDocumentFormDraft draft) {
  final payload = draft.payload;
  final order = payload['kind'] == 'order';
  if (order || payload['kind'] == 'acceptance') {
    final dates = <String, StandaloneTradeDateError>{
      'issue_date': order
          ? StandaloneTradeDateError.orderIssueDate
          : StandaloneTradeDateError.acceptanceIssueDate,
      if (!order) 'order_date': StandaloneTradeDateError.orderDate,
      if (order) 'period_start': StandaloneTradeDateError.periodStart,
      if (order) 'period_end': StandaloneTradeDateError.periodEnd,
    };
    for (final entry in dates.entries) {
      final value = payload[entry.key];
      final parsed = value is String ? DateTime.tryParse(value) : null;
      if (value is! String ||
          !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
          parsed == null ||
          parsed.toIso8601String().substring(0, 10) != value) {
        throw StandaloneTradeDateException(entry.value);
      }
    }
  }
  // Retain every original amount/party/terms/seal/prose validation unchanged.
  draft.validateForSave();
}

String standaloneTradeGenerationMessage(Object error) {
  if (error is StandaloneTradeDateException) {
    final label = switch (error.field) {
      StandaloneTradeDateError.orderIssueDate => '発行日',
      StandaloneTradeDateError.acceptanceIssueDate => '承諾日',
      StandaloneTradeDateError.orderDate => '注文書の日付',
      StandaloneTradeDateError.periodStart => '工期開始日',
      StandaloneTradeDateError.periodEnd => '工期終了日',
    };
    return '$labelをYYYY-MM-DDで入力してください。';
  }
  // Font/PDF/asset errors and arbitrary FormatException/StateError remain generic.
  return '帳票を作成できません。入力内容を確認してください。';
}

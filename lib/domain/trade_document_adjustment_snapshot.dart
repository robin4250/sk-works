class SavedTradeDocumentAdjustment {
  const SavedTradeDocumentAdjustment({required this.id, required this.title,
    required this.amountYen, required this.sign, required this.calculationMode});
  final String id, title, sign, calculationMode;
  final int amountYen;
  int get signedYen => sign == 'minus' ? -amountYen : amountYen;
  bool get isFinalAmount => calculationMode == 'settlement_yen';

  static List<SavedTradeDocumentAdjustment> parse(Map<String, dynamic> snapshot) {
    if (!snapshot.containsKey('document_adjustments_v1')) return const [];
    final raw = snapshot['document_adjustments_v1'];
    if (raw is! List) throw const FormatException('加減算明細を確認できません。');
    final ids = <String>{};
    final result = <SavedTradeDocumentAdjustment>[];
    for (final item in raw) {
      if (item is! Map || item['entry_id'] is! String || item['title'] is! String ||
          item['amount_yen'] is! int || (item['amount_yen'] as int) < 1 ||
          (item['amount_yen'] as int) > 2147483647 ||
          !const ['plus', 'minus'].contains(item['sign']) ||
          !const ['before_charges', 'settlement_yen'].contains(item['calculation_mode'])) {
        throw const FormatException('保存済みの加減算明細を確認できません。');
      }
      final id = item['entry_id'] as String, title = (item['title'] as String).trim();
      if (!RegExp(r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$').hasMatch(id) ||
          !ids.add(id.toLowerCase()) || title.isEmpty || title.runes.length > 120) {
        throw const FormatException('加減算項目の識別情報を確認できません。');
      }
      result.add(SavedTradeDocumentAdjustment(id:id,title:title,
        amountYen:item['amount_yen'] as int,sign:item['sign'] as String,
        calculationMode:item['calculation_mode'] as String));
    }
    return List.unmodifiable(result);
  }
}

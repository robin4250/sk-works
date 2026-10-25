/// Display evidence taken only from the statement's saved unit resolution.
/// It never loads today's settings or changes any saved money.
class PayrollRecordedUnitEvidence {
  const PayrollRecordedUnitEvidence(this.quantityLabel, this.calculation);

  final String quantityLabel;
  final String calculation;
}

PayrollRecordedUnitEvidence? recordedPayrollUnitEvidence(
  Map<String, dynamic> detail, {
  required String name,
  required String section,
  required num displayedAmount,
}) {
  final resolution = detail['unit_resolution'];
  if (resolution is! Map || resolution['contract_version'] != 1 ||
      resolution['blocked'] == true || resolution['items'] is! List ||
      !displayedAmount.isFinite || displayedAmount <= 0) {
    return null;
  }
  final matches = (resolution['items'] as List).whereType<Map>().where((item) =>
      item['name']?.toString().trim() == name.trim() && item['section'] == section).toList();
  // The table merges equal labels. Never attribute one item's basis to a
  // combined amount, an adjustment, or a different item sharing its label.
  if (matches.length != 1) return null;
  final item = matches.single;
  final amount = item['amount_yen'];
  final rate = item['rate_yen'];
  final quantity = item['quantity'];
  final suffix = const {'hour': '時間', 'day': '日', 'month': '月'}[item['unit']];
  if (suffix == null || amount is! num || rate is! num || quantity is! num ||
      !amount.isFinite || !rate.isFinite || !quantity.isFinite ||
      rate < 0 || quantity < 0 || amount != displayedAmount) {
    return null;
  }
  final product = rate * quantity;
  if (!product.isFinite || product.round() != amount ||
      num.tryParse(_decimal(rate)) != rate || num.tryParse(_decimal(quantity)) != quantity) {
    return null;
  }
  final count = _decimal(quantity);
  return PayrollRecordedUnitEvidence('$count$suffix',
      '${_money(rate)}円 × $count$suffix');
}

String _decimal(num value) => value.toStringAsFixed(4)
    .replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');

String _money(num value) {
  final parts = _decimal(value).split('.');
  final whole = parts.first.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return parts.length == 1 ? whole : '$whole.${parts.last}';
}

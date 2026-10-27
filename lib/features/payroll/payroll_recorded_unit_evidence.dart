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
  // These sources are saved alongside the statement, never today's settings.
  // Legacy attendance totals alone do not contain an attributable unit price.
  final primary = detail['unit_resolution'];
  final attendance = detail['attendance_unit_evidence'];
  if (primary is Map && primary['blocked'] == true) {
    return null;
  }
  final primaryItems = primary is Map && primary['items'] is List
      ? (primary['items'] as List).whereType<Map>().where((item) =>
          item['name']?.toString().trim() == name.trim() && item['section'] == section)
      : const Iterable<Map>.empty();
  if (primaryItems.isEmpty && attendance is Map) {
    return _attendanceEvidence(attendance, name: name, section: section,
        displayedAmount: displayedAmount);
  }
  final resolution = primary;
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

PayrollRecordedUnitEvidence? _attendanceEvidence(Map resolution, {
  required String name, required String section, required num displayedAmount,
}) {
  if (resolution['contract_version'] != 1 || resolution['blocked'] == true ||
      resolution['items'] is! List || !displayedAmount.isFinite || displayedAmount <= 0) {
    return null;
  }
  final items = (resolution['items'] as List).whereType<Map>().where((item) =>
      item['name']?.toString().trim() == name.trim() && item['section'] == section).toList();
  if (items.isEmpty) return null;
  num amount = 0, quantity = 0;
  final formulas = <String>[];
  final units = <String>{};
  for (final item in items) {
    final rate = item['rate_yen'], count = item['quantity'], money = item['amount_yen'];
    final suffix = const {'hour': '時間', 'day': '日', 'month': '月', 'count': '回'}[item['unit']];
    if (suffix == null || rate is! num || count is! num || money is! num ||
        !rate.isFinite || !count.isFinite || !money.isFinite || rate < 0 || count < 0 ||
        !(rate * count).isFinite || (rate * count).round() != money ||
        num.tryParse(_decimal(rate)) != rate || num.tryParse(_decimal(count)) != count) {
      return null;
    }
    amount += money; quantity += count; units.add(suffix);
    final category = const {'day': '日勤', 'night': '夜勤',
      'holiday': '休日', 'holiday_night': '休日夜勤'}[item['category']];
    formulas.add('${items.length > 1 && category != null ? '$category ' : ''}${_money(rate)}円 × ${_decimal(count)}$suffix');
  }
  if (amount != displayedAmount) return null;
  return PayrollRecordedUnitEvidence(units.length == 1 ? '${_decimal(quantity)}${units.single}' : '内訳参照',
      formulas.join('／'));
}


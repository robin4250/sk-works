/// Presentation-only transfer from a statement's immutable saved snapshot.
/// Returns null unless every saved amount can be attributed without guessing.
class PayrollPositionTransfer {
  const PayrollPositionTransfer(this.entries, this.rate, this.days, this.isAverage,
      {this.reallocatedNames = const {}});
  final Map<String, Object?> entries;
  final int? rate;
  final num? days;
  final bool isAverage;
  final Set<String> reallocatedNames;
}

PayrollPositionTransfer? payrollPositionTransfer(
    Map<String, dynamic> detail, Map<String, Object?> original) {
  final snap = detail['position_transfer_snapshot'];
  if (snap is Map && snap['version'] == 2) {
    return _baseToAllowance(snap, original);
  }
  if (snap is! Map || snap['version'] != 1 || snap['enabled'] != true ||
      snap['pay_type'] != 'daily') {
    return null;
  }
  final base = _yen(original['基本給']);
  final parsed = _parseItems(snap['items']);
  if (base == null || parsed == null || original.containsKey('基本給の調整額')) {
    return null;
  }
  for (final entry in parsed.amounts.entries) {
    final name = entry.key;
    if (_yen(original[name]) != entry.value) return null;
    // Reject labels merged from more than one configured source row.
    for (final container in [detail['custom_earnings'],
        (detail['unit_resolution'] is Map) ? (detail['unit_resolution'] as Map)['items'] : null]) {
      if (container is List && container.whereType<Map>().where((entry) =>
          entry['name']?.toString().trim() == name &&
          (entry['section'] == null || entry['section'] == 'earning')).length > 1) {
        return null;
      }
    }
  }
  final transferred = parsed.total;
  final evidence = detail['attendance_unit_evidence'];
  if (evidence is! Map || evidence['contract_version'] != 1 ||
      evidence['blocked'] == true || evidence['items'] is! List) {
    return null;
  }
  final items = (evidence['items'] as List).whereType<Map>().where((x) =>
      x['name'] == '基本給' && x['section'] == 'earning').toList();
  if (items.isEmpty) {
    return null;
  }
  var days = 0.0;
  var recordedBase = 0;
  final categories = <String>{};
  for (final row in items) {
    final category = row['category'];
    final rate = _yen(row['rate_yen']);
    final amount = _yen(row['amount_yen']);
    final quantity = row['quantity'];
    if (row['unit'] != 'day' || category is! String || category.isEmpty ||
        !categories.add(category) || rate == null || amount == null ||
        quantity is! num || !quantity.isFinite || quantity <= 0 ||
        (quantity * 1000).round() != quantity * 1000 ||
        (rate * quantity).round() != amount) {
      return null;
    }
    days += quantity;
    recordedBase += amount;
  }
  if (days <= 0 || days > 31 || recordedBase != base) {
    return null;
  }
  // Multiple saved rates require a weighted average. Label it as such in the PDF.
  // Round positive values half up to the nearest 500 yen.
  final displayRate = (((base + transferred) / days) / 500).round() * 500;
  final num displayDays = days == days.roundToDouble() ? days.toInt() : days;
  final displayBase = (displayRate * days).round();
  final adjustment = base + transferred - displayBase;
  final result = Map<String, Object?>.from(original);
  result['基本給'] = displayBase;
  for (final name in parsed.amounts.keys) {
    result.remove(name);
  }
  if (adjustment != 0) {
    result['基本給の調整額'] = adjustment;
  }
  return PayrollPositionTransfer(Map.unmodifiable(result), displayRate, displayDays, items.length > 1);
}

/// A known non-daily saved setting is inapplicable, rather than a failed daily
/// transfer. Never calculates a new rate or changes the saved monetary values.
/// Unknown/malformed requested snapshots remain eligible for the PDF warning.
bool validNonDailyPayrollPositionTransferSnapshot(Map<String, dynamic> detail) {
  final snap = detail['position_transfer_snapshot'];
  return snap is Map && snap.keys.toSet().containsAll(
      const ['version', 'enabled', 'pay_type', 'items']) && snap.length == 4 &&
      snap['version'] == 1 && snap['enabled'] == true &&
      (snap['pay_type'] == 'monthly' || snap['pay_type'] == 'hourly') &&
      _parseItems(snap['items']) != null;
}

int? _yen(Object? v) => v is num && v.isFinite && v >= 0 &&
    v <= 2147483647 && v == v.round() ? v.toInt() : null;

class _TransferItems {
  const _TransferItems(this.amounts, this.total);
  final Map<String, int> amounts;
  final int total;
}

// Shared with daily attribution: valid non-daily settings must not bypass name,
// amount, duplicate or aggregate bounds that would reject the daily setting.
_TransferItems? _parseItems(Object? rawItems) {
  if (rawItems is! List || rawItems.isEmpty) return null;
  final amounts = <String, int>{};
  var total = 0;
  for (final raw in rawItems) {
    if (raw is! Map || raw['name'] is! String) return null;
    final name = (raw['name'] as String).trim();
    final amount = _yen(raw['amount_yen']);
    if (name.isEmpty || name == '基本給' || name == '基本給の調整額' ||
        amount == null || amount == 0 || amounts.containsKey(name)) {
      return null;
    }
    amounts[name] = amount;
    total += amount;
    if (total > 2147483647) return null;
  }
  return _TransferItems(amounts, total);
}

// Version 2 reallocates saved basic earnings; version 1 retains its historical
// opposite-direction presentation. Never derive this from current settings.
PayrollPositionTransfer? _baseToAllowance(
    Map snapshot, Map<String, Object?> original) {
  if (snapshot.length != 4 || !snapshot.keys.toSet().containsAll(
      const ['version', 'enabled', 'pay_type', 'items']) ||
      snapshot['enabled'] != true ||
      !const ['daily', 'hourly', 'monthly'].contains(snapshot['pay_type'])) {
    return null;
  }
  final base = _yen(original['基本給']);
  final parsed = _parseItems(snapshot['items']);
  if (base == null || parsed == null || parsed.total > base ||
      original.containsKey('基本給の調整額')) {
    return null;
  }
  final result = Map<String, Object?>.from(original);
  for (final entry in parsed.amounts.entries) {
    if (const ['残業手当', '早出手当', '深夜手当', '休日手当', '休日出勤手当',
        '夜勤手当', '有給手当'].contains(entry.key)) {
      return null;
    }
    final existing = original.containsKey(entry.key) ? _yen(original[entry.key]) : 0;
    if (existing == null || existing != 0) {
      return null;
    }
    result[entry.key] = existing + entry.value;
  }
  result['基本給'] = base - parsed.total;
  return PayrollPositionTransfer(Map.unmodifiable(result), null, null, false,
      reallocatedNames: Set.unmodifiable(parsed.amounts.keys));
}

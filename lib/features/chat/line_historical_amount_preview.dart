import '../../domain/rate_formula_settings.dart';

/// A local estimate only: never marks a candidate confirmed or writes an invoice.
/// Rounds category lines, then welfare and tax per site, like the invoice bridge.
class LineHistoricalAmountPreview {
  const LineHistoricalAmountPreview(this.sites, this.pendingRows, this.incompleteRows);
  final List<({String name, int base, int welfare, int tax, int total})> sites;
  final int pendingRows, incompleteRows;
  int get total => sites.fold(0, (sum, site) => sum + site.total);
}

LineHistoricalAmountPreview lineHistoricalAmountPreview(List<Map<String, dynamic>> rows) {
  const formula = RateFormulaSettings();
  final groups = <String, ({String site, String name, String category, List<double> quantities, Map<String, int> allowances})>{};
  var pending = 0, incomplete = 0;
  for (final row in rows.where((row) => row['excluded'] != true)) {
    if (row['confirmed'] != true) pending++;
    double? quantity(String key) {
      final raw = row[key];
      final value = raw is num ? raw.toDouble() : double.tryParse('$raw');
      return value != null && value.isFinite && value >= 0 ? value : null;
    }
    final days = quantity('man_days'), overtime = quantity('overtime_hours'), early = quantity('early_hours');
    final name = row['formal_site_name']?.toString().trim();
    final original = row['site_name']?.toString().trim() ?? '';
    final site = row['site_id']?.toString() ?? original;
    final category = row['work_category']?.toString();
    final rawAllowances = row['allowance_names'];
    final allowances = rawAllowances is List ? rawAllowances.toSet() : <dynamic>{};
    if (site.isEmpty || original.isEmpty || !['day', 'night', 'holiday', 'holiday_night'].contains(category) ||
        ![0.5, 1.0].contains(days) || overtime == null || overtime > 24 || early == null || early > 24 ||
        rawAllowances is! List ||
        allowances.any((name) => !['PC', 'PC手当', '鉄骨', '鉄骨手当'].contains(name)) ||
        (row['steel_allowance'] == true && allowances.isEmpty) ||
        (row['review_reason']?.toString().contains('複数行') ?? false)) {
      incomplete++;
      continue;
    }
    final group = groups.putIfAbsent('$site:$category', () => (
      site: site, name: name != null && name.isNotEmpty ? name : original,
      category: category!, quantities: [0.0, 0.0, 0.0], allowances: <String, int>{}));
    group.quantities[0] += days!;
    group.quantities[1] += overtime;
    group.quantities[2] += early;
    for (final allowance in allowances) {
      final key = allowance == 'PC' || allowance == 'PC手当' ? 'PC' : '鉄骨';
      // PC and PC手当 are the same allowance, not two payments.
      if (allowances.contains(key) && allowance != key) continue;
      group.allowances[key] = (group.allowances[key] ?? 0) + 1;
    }
  }
  final bases = <String, int>{}, names = <String, String>{};
  for (final group in groups.values) {
    final day = switch (group.category) {
      'night' => formula.night(32800), 'holiday' => formula.holiday(32800),
      'holiday_night' => formula.holidayNight(32800), _ => 32800,
    };
    final amount = (group.quantities[0] * day).round() +
      (group.quantities[1] * formula.overtime(32800)).round() +
      (group.quantities[2] * formula.early(32800)).round() +
      group.allowances.values.fold<int>(0, (sum, count) => sum + count * 3000);
    bases[group.site] = (bases[group.site] ?? 0) + amount;
    names[group.site] = group.name;
  }
  return LineHistoricalAmountPreview([for (final entry in bases.entries) (
    name: names[entry.key]!, base: entry.value,
    welfare: (entry.value * 1500 / 10000).round(),
    tax: ((entry.value + (entry.value * 1500 / 10000).round()) * 1000 / 10000).round(),
    total: entry.value + (entry.value * 1500 / 10000).round() +
      ((entry.value + (entry.value * 1500 / 10000).round()) * 1000 / 10000).round(),
  )], pending, incomplete);
}

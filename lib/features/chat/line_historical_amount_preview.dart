import '../../domain/rate_formula_settings.dart';
import '../../domain/invoice_engine.dart';

int lineHistoricalDefaultDayRate(String category) => switch (category) {
  'night' => const RateFormulaSettings().night(32800),
  'holiday' => const RateFormulaSettings().holiday(32800),
  'holiday_night' => const RateFormulaSettings().holidayNight(32800),
  _ => 32800,
};

/// A local estimate only: never marks a candidate confirmed or writes an invoice.
/// Rounds category lines, then welfare and tax per site, like the invoice bridge.
class LineHistoricalAmountPreview {
  const LineHistoricalAmountPreview(this.sites, this.pendingRows, this.incompleteRows, this.calculations,
      {this.workDates = const [], this.includedRows = 0});
  final List<({String name, int base, int welfare, int tax, int total})> sites;
  final int pendingRows, incompleteRows;
  /// Dates of exactly the rows included in the reference calculation below.
  final List<String> workDates;
  final int includedRows;
  final List<SiteInvoiceCalculation> calculations;
  InvoiceCalculationResult invoice(DateTime month) => InvoiceEngine.calculate(
    customerId: '取引先未確認（参考）', billingPeriod: '${month.year}年${month.month}月',
    detailMode: InvoiceDetailMode.siteBreakdownOnInvoice,
    sites: calculations, taxRateBps: 1000, invoiceNumber: '参考・未確認',
    taxYenOverride: sites.fold<int>(0, (sum, site) => sum + site.tax),
  );
  int get total => sites.fold(0, (sum, site) => sum + site.total);
}

LineHistoricalAmountPreview lineHistoricalAmountPreview(List<Map<String, dynamic>> rows) {
  const formula = RateFormulaSettings();
  final groups = <String, ({String site, String name, String category, List<double> quantities, Map<String, int> allowances})>{};
  var pending = 0, incomplete = 0, included = 0;
  final dates = <String>{};
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
    included++;
    final date = row['work_date'];
    if (date is String) dates.add(date);
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
  final linesBySite = <String, List<InvoiceLine>>{}, names = <String, String>{};
  for (final group in groups.values) {
    final day = lineHistoricalDefaultDayRate(group.category);
    linesBySite.putIfAbsent(group.site, () => []).addAll([
      InvoiceLine(label: '作業（${group.category}）', quantity: group.quantities[0], unitPriceYen: day),
      if (group.quantities[1] > 0) InvoiceLine(label: '残業', quantity: group.quantities[1], unitPriceYen: formula.overtime(day)),
      if (group.quantities[2] > 0) InvoiceLine(label: '早出', quantity: group.quantities[2], unitPriceYen: formula.early(day)),
      for (final entry in group.allowances.entries) InvoiceLine(label: '${entry.key}手当', quantity: entry.value.toDouble(), unitPriceYen: 3000),
    ]);
    names[group.site] = group.name;
  }
  final calculations = [for (final entry in linesBySite.entries) SiteInvoiceCalculation(
    siteId: entry.key, siteName: names[entry.key]!, lines: entry.value, welfareRateBps: 1500,
  )];
  return LineHistoricalAmountPreview([for (final site in calculations) (
    name: site.siteName, base: site.baseAmountYen, welfare: site.welfareAmountYen,
    tax: InvoiceEngine.calculate(customerId: '参考', billingPeriod: '参考',
      detailMode: InvoiceDetailMode.siteBreakdownOnInvoice, sites: [site], taxRateBps: 1000).taxYen,
    total: InvoiceEngine.calculate(customerId: '参考', billingPeriod: '参考',
      detailMode: InvoiceDetailMode.siteBreakdownOnInvoice, sites: [site], taxRateBps: 1000).grandTotalYen,
  )], pending, incomplete, calculations,
    workDates: List.unmodifiable(dates.toList()..sort()), includedRows: included);
}

Map<String, dynamic> insuranceEvidenceFixture() {
  final premiums = {'健康保険料': 15760, '厚生年金保険': 31110, '介護保険料': 2592,
    '雇用保険料': 1700, '子ども・子育て支援金': 368};
  final specs = [('health_insurance', 320000, 4925000, 15760),
    ('pension_insurance', 340000, 9150000, 31110),
    ('nursing_insurance', 320000, 810000, 2592),
    ('employment_insurance', 340000, 500000, 1700),
    ('child_support', 320000, 115000, 368)];
  return {...premiums, 'tax_calculation': {
    'calculator_version': 'payroll-tax-20261014-overrides-v1', 'condition_version': 1,
    'conditions_start': '2026-10-01', 'payment_date': '2026-11-25',
    'conditions': {'insurance_mode': 'rates', 'health': true, 'pension': true,
      'employment': true, 'nursing': true, 'child_support': true,
      'health_base_yen': 320000, 'pension_base_yen': 340000,
      'insurance_basis_reference': {'schema': 1, 'from': '2026-04-01', 'to': '2026-06-01',
        'average_monthly_income_yen': 500000, 'source': 'manual',
        'observed_months': 0, 'history_fingerprint': null}},
    'premiums': premiums,
    'rates': [for (final spec in specs) {'insurance_month': '2026-10-01',
      'base_yen': spec.$2, 'employee_yen': spec.$4, 'item_id': spec.$1, 'version': 1,
      'value': {'kind': spec.$1, 'employee': spec.$3, 'payroll_month': '2026-09-01',
        'insurance_month': '2026-09-01', 'payment_month': '2026-10-01'}}],
  }};
}

/// Synthetic saved statement evidence at the existing insurance range limits.
/// These are fixture calculations, never a live rate lookup or real payroll.
Map<String, dynamic> insuranceBoundaryEvidenceFixture({required int healthBase,
    required int pensionBase, int healthRate = 5000000,
    String month = '2026-10-01'}) {
  final detail = insuranceEvidenceFixture();
  final tax = detail['tax_calculation'] as Map;
  final target = DateTime.parse(month);
  String ym(DateTime value) => '${value.year}-${value.month.toString().padLeft(2, '0')}-01';
  final previous = ym(DateTime(target.year, target.month - 1));
  final next = DateTime(target.year, target.month + 1, 25);
  final specs = [
    ('健康保険料', 'health_insurance', healthBase, healthRate),
    ('厚生年金保険', 'pension_insurance', pensionBase, 9150000),
    ('介護保険料', 'nursing_insurance', healthBase, 810000),
    ('雇用保険料', 'employment_insurance', 500000, 500000),
    ('子ども・子育て支援金', 'child_support', healthBase, 115000),
  ];
  final premiums = {for (final spec in specs)
    spec.$1: (spec.$3 * spec.$4 / 100000000).round()};
  detail.addAll(premiums);
  tax['premiums'] = premiums;
  tax['payment_date'] = '${next.year}-${next.month.toString().padLeft(2, '0')}-25';
  (tax['conditions'] as Map).addAll({'health_base_yen': healthBase,
    'pension_base_yen': pensionBase});
  tax['rates'] = [for (final spec in specs) {
    'insurance_month': month, 'base_yen': spec.$3,
    'employee_yen': premiums[spec.$1], 'item_id': spec.$2, 'version': 1,
    'value': {'kind': spec.$2, 'employee': spec.$4,
      'payroll_month': previous, 'insurance_month': previous, 'payment_month': month},
  }];
  return detail;
}


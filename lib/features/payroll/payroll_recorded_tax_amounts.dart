/// Reads already persisted calculation amounts. It never calculates premiums or
/// changes stored settings, statement totals or finalization state.
const recordedPayrollInsuranceNames = <String>[
  '健康保険料', '介護保険料', '厚生年金保険', '雇用保険料', '子ども・子育て支援金',
];

// Both persisted producer contracts have the same conditions/premiums fields.
const _recordedPayrollTaxCalculators = {
  'payroll-tax-20261010-v1',
  'payroll-tax-20261014-overrides-v1',
  'payroll-tax-personal-uid-v1',
};

int? _yen(Object? value) => value is num && value.isFinite &&
    value >= 0 && value <= 2147483647 && value == value.round()
    ? value.toInt() : null;

bool hasRecordedPayrollTaxCalculation(Map detail, {required String month}) {
  final tax = detail['tax_calculation'];
  if (tax is! Map || tax['blocked'] == true ||
      !_recordedPayrollTaxCalculators.contains(tax['calculator_version']) ||
      tax['condition_version'] is! int || (tax['condition_version'] as int) < 1 ||
      tax['conditions_start'] is! String || tax['premiums'] is! Map ||
      tax['conditions'] is! Map) {
    return false;
  }
  final start = tax['conditions_start'] as String;
  return RegExp(r'^20\d{2}-(0[1-9]|1[0-2])-01$').hasMatch(start) &&
      RegExp(r'^20\d{2}-(0[1-9]|1[0-2])-01$').hasMatch(month) &&
      start.compareTo(month) <= 0 &&
      const ['rates', 'manual'].contains((tax['conditions'] as Map)['insurance_mode']) &&
      recordedPayrollInsuranceNames.any((name) =>
          _yen(detail.containsKey(name) ? detail[name] : (tax['premiums'] as Map)[name]) != null);
}

Map<String, int> recordedPayrollInsuranceAmounts(Map detail, {required String month}) {
  if (!hasRecordedPayrollTaxCalculation(detail, month: month)) {
    return const {};
  }
  final premiums = (detail['tax_calculation'] as Map)['premiums'] as Map;
  final result = <String, int>{};
  for (final name in recordedPayrollInsuranceNames) {
    // An explicit scalar, including zero or an invalid value, is authoritative.
    // Never replace it with a different calculation snapshot.
    final amount = _yen(detail.containsKey(name) ? detail[name] : premiums[name]);
    if (amount != null) { result[name] = amount; }
  }
  return result;
}

Map<String, dynamic> detailWithRecordedPayrollInsurance(
  Map<String, dynamic> detail, {required String month}
) => {...detail, ...recordedPayrollInsuranceAmounts(detail, month: month)};

/// A display of the statement's saved withholding basis, never a calculation
/// using current settings and never a change to the stored deduction.
class PayrollRecordedIncomeTaxEvidence {
  const PayrollRecordedIncomeTaxEvidence(this.summary, {this.calculationLines = const []});
  final String summary;
  final List<String> calculationLines;
}

String recordedPayrollIncomeTaxExplanation(Map<String, dynamic> detail, {
  required String month, required num displayedAmount,
}) => recordedPayrollIncomeTaxEvidence(detail, month: month,
    displayedAmount: displayedAmount).summary;

PayrollRecordedIncomeTaxEvidence recordedPayrollIncomeTaxEvidence(Map<String, dynamic> detail, {
  required String month, required num displayedAmount,
}) {
  const unavailable = '計算根拠の保存記録なし';
  final tax = detail['tax_calculation'];
  if (tax is! Map || tax['blocked'] == true ||
      !const {'payroll-tax-20261010-v1', 'payroll-tax-20261014-overrides-v1', 'payroll-tax-personal-uid-v1'}
          .contains(tax['calculator_version']) ||
      tax['condition_version'] is! int || tax['condition_version'] < 1 ||
      !_month(tax['conditions_start']) || !_month(month) ||
      (tax['conditions_start'] as String).compareTo(month) > 0 ||
      tax['conditions'] is! Map || !displayedAmount.isFinite ||
      displayedAmount < 0 || displayedAmount != displayedAmount.round()) {
    return const PayrollRecordedIncomeTaxEvidence(unavailable);
  }
  final amount = _yen(tax['income_tax_yen']);
  if (amount == null || amount != displayedAmount) {
    return const PayrollRecordedIncomeTaxEvidence('保存された所得税額と不一致');
  }
  final conditions = tax['conditions'] as Map;
  final mode = conditions['income_mode'];
  final overrides = tax['deduction_overrides'];
  final overridden = overrides is Map && overrides.containsKey('income_tax');
  if (overridden && _yen(overrides['income_tax']) != amount) {
    return const PayrollRecordedIncomeTaxEvidence(unavailable);
  }
  // Legacy fixed settings are not part of this snapshot; an explicit saved
  // override can be identified, but the original fixed amount cannot be proved.
  if (mode == 'fixed') {
    return PayrollRecordedIncomeTaxEvidence(overridden ? '手動修正（保存額）' : '固定額の計算根拠は未記録');
  }
  if (!const {'koh', 'otsu'}.contains(mode) ||
      tax['income_table'] != 'nta-monthly-2026-c583c9c3' ||
      !_paymentIn2026(tax['payment_date']) ||
      conditions['dependents'] is! int || conditions['dependents'] < 0 ||
      conditions['dependents'] > 99) {
    return const PayrollRecordedIncomeTaxEvidence(unavailable);
  }
  final gross = _yen(tax['gross_with_adjustments']), social = _yen(tax['social_yen']);
  final nonTaxable = _yen(conditions['non_taxable_yen']);
  final additional = _yen(conditions['additional_social_deduction_yen']);
  final base = _yen(tax['income_tax_base_yen']);
  if (gross == null || social == null || nonTaxable == null || additional == null || base == null ||
      nonTaxable > gross || base != (gross - nonTaxable - social - additional).clamp(0, gross)) {
    return const PayrollRecordedIncomeTaxEvidence('保存された課税対象額と不一致');
  }
  final automatic = tax['calculator_version'] == 'payroll-tax-20261010-v1'
      ? amount : _yen(tax['automatic_income_tax_yen']);
  if (automatic == null || (!overridden && automatic != amount)) {
    return const PayrollRecordedIncomeTaxEvidence(unavailable);
  }
  final column = mode == 'koh' ? '甲欄・扶養${conditions['dependents']}人' : '乙欄';
  final summary = '対象${_money(base)}円／R8月額表 $column${overridden ? '・手動修正' : ''}';
  final beforeFloor = gross - nonTaxable - social - additional;
  final basis = '所得税対象額：支給額 ${_money(gross)}円 − 非課税額 ${_money(nonTaxable)}円'
      ' − 社会保険料等 ${_money(social)}円 − 他項目で控除済みの社会保険料等 ${_money(additional)}円'
      ' ＝ ${_money(base)}円${beforeFloor < 0 ? '（0円未満は0円）' : ''}';
  final tableColumn = mode == 'koh' ? column
      : '乙欄・従たる給与の申告扶養${conditions['dependents']}人';
  final method = '令和8年月額表：$tableColumn、対象 ${_money(base)}円 → 自動計算 ${_money(automatic)}円'
      '${overridden ? '／手動修正後 ${_money(amount)}円' : ''}';
  return PayrollRecordedIncomeTaxEvidence(summary, calculationLines: [basis, method]);
}

int? _yen(Object? value) => value is num && value.isFinite && value >= 0 &&
    value <= 2147483647 && value == value.round() ? value.toInt() : null;
bool _month(Object? value) => value is String &&
    RegExp(r'^20\d{2}-(0[1-9]|1[0-2])-01$').hasMatch(value);
bool _paymentIn2026(Object? value) {
  if (value is! String || !RegExp(r'^2026-\d{2}-\d{2}$').hasMatch(value)) {
    return false;
  }
  final parsed = DateTime.tryParse(value);
  return parsed != null && parsed.toIso8601String().substring(0, 10) == value;
}

String _money(int amount) => amount.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

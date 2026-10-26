import 'payroll_insurance_basis_reference.dart';
import 'payroll_recorded_tax_amounts.dart';

/// Display-only evidence from this statement's saved calculation. No live
/// condition/rate read and no premium recalculation or guessed provenance.
class PayrollInsuranceCalculationEvidence {
  const PayrollInsuranceCalculationEvidence({required this.rows,
    required this.referenceText, required this.provenanceText});
  final List<PayrollInsuranceEvidenceRow> rows;
  final String referenceText, provenanceText;
  bool get isEmpty => rows.isEmpty;

  static PayrollInsuranceCalculationEvidence fromDetail(Map<String, dynamic> detail,
      {required String month}) {
    final rawTax = detail['tax_calculation'];
    if (rawTax is Map && rawTax['blocked'] == true) {
      return const PayrollInsuranceCalculationEvidence(rows: [],
        referenceText: '計算保留中', provenanceText: '保留中の金額から計算根拠を表示しません');
    }
    final recorded = hasRecordedPayrollTaxCalculation(detail, month: month);
    final tax = recorded ? rawTax as Map : const {};
    final conditions = tax['conditions'] is Map ? tax['conditions'] as Map : const {};
    final premiums = tax['premiums'] is Map ? tax['premiums'] as Map : const {};
    final overrides = tax['deduction_overrides'] is Map ? tax['deduction_overrides'] as Map : const {};
    final rows = <PayrollInsuranceEvidenceRow>[];
    for (final entry in const {
      '健康保険料': ('health_insurance', 'health'),
      '厚生年金保険': ('pension_insurance', 'pension'),
      '介護保険料': ('nursing_insurance', 'nursing'),
      '雇用保険料': ('employment_insurance', 'employment'),
      '子ども・子育て支援金': ('child_support', 'child_support'),
    }.entries) {
      final amount = insuranceEvidenceYen(detail.containsKey(entry.key) ? detail[entry.key] : premiums[entry.key]);
      if (amount == null) continue;
      final kind = entry.value.$1;
      // A saved non-enrollment condition suppresses only a zero row. Preserve
      // any nonzero deduction, including an override, so printed totals reconcile.
      if (recorded && conditions[entry.value.$2] == false && amount == 0) continue;
      String formula;
      if (!recorded) {
        formula = '控除額 ${insuranceEvidenceMoney(amount)}（計算根拠の保存記録なし）';
      } else if (conditions['insurance_mode'] == 'manual') {
        final savedManual = conditions['manual_insurance_premiums'];
        formula = savedManual is Map && insuranceEvidenceYen(savedManual[kind]) == amount
            ? '本人負担月額を手入力 ＝ ${insuranceEvidenceMoney(amount)}'
            : '控除額 ${insuranceEvidenceMoney(amount)}（保存済みの手入力月額を確認できません）';
      } else {
        final matches = tax['rates'] is List ? (tax['rates'] as List).where((row) =>
          row is Map && row['value'] is Map && (row['value'] as Map)['kind'] == kind).toList() : const [];
        if (matches.length != 1 || !_applicableRate(matches.single as Map, tax, month)) {
          formula = '控除額 ${insuranceEvidenceMoney(amount)}（適用料率の保存記録を確認できません）';
        } else {
          final rate = matches.single as Map;
          final base = insuranceEvidenceYen(rate['base_yen']);
          final calculated = insuranceEvidenceYen(rate['employee_yen']);
          final value = rate['value'] as Map;
          final scaled = insuranceEvidenceYen(value['employee']);
          if (base == null || calculated == null || scaled == null || scaled > 100000000) {
            formula = '控除額 ${insuranceEvidenceMoney(amount)}（計算根拠の保存記録を確認できません）';
          } else if (!_savedArithmeticMatches(base, scaled, calculated)) {
            formula = '控除額 ${insuranceEvidenceMoney(amount)}（保存された計算基準・料率と不一致）';
          } else {
            final baseName = kind == 'employment_insurance' ? '当月対象賃金' : base == 0 ? '計算対象額' : '標準報酬月額';
            final calculation = '$baseName ${insuranceEvidenceMoney(base)} × ${insuranceEvidencePercent(scaled)}% ＝ ${insuranceEvidenceMoney(calculated)}';
            if (amount == calculated) {
              formula = calculation;
            } else if (insuranceEvidenceYen(overrides[kind]) == amount) {
              formula = '$calculation／手動修正後 ${insuranceEvidenceMoney(amount)}';
            } else {
              formula = '控除額 ${insuranceEvidenceMoney(amount)}（保存された計算額 ${insuranceEvidenceMoney(calculated)} と不一致）';
            }
          }
        }
      }
      rows.add(PayrollInsuranceEvidenceRow(entry.key, amount, formula));
    }
    return PayrollInsuranceCalculationEvidence(rows: List.unmodifiable(rows),
      referenceText: _reference(conditions['insurance_basis_reference']),
      provenanceText: '平均月収と標準報酬月額の採用関係は未記録。金額・料率はこの明細の保存値です。');
  }

  // Display validation only. Both stored floor/ceil outcomes are legitimate
  // rounding evidence; never recalculate or write a premium here.
  static bool _savedArithmeticMatches(int base, int scaledRate, int amount) {
    final numerator = BigInt.from(base) * BigInt.from(scaledRate);
    final denominator = BigInt.from(100000000);
    final floor = numerator ~/ denominator;
    final ceil = (numerator + denominator - BigInt.one) ~/ denominator;
    final recorded = BigInt.from(amount);
    return recorded >= floor && recorded <= ceil;
  }

  static bool _applicableRate(Map row, Map tax, String month) {
    final value = row['value'] as Map;
    final registered = _month(value['payroll_month']);
    final insured = _month(value['insurance_month']);
    final paid = _month(value['payment_month']);
    final target = _month(month);
    final actualInsured = _month(row['insurance_month']);
    final payment = tax['payment_date'];
    final actualPaid = payment is String && payment.length >= 7 ? _month('${payment.substring(0, 7)}-01') : null;
    return registered != null && insured != null && paid != null && target != null &&
      actualInsured != null && actualPaid != null && registered <= target &&
      actualInsured - target == insured - registered && actualPaid - target == paid - registered;
  }

  static int? _month(Object? value) {
    if (value is! String || !RegExp(r'^20\d{2}-(0[1-9]|1[0-2])-01$').hasMatch(value)) return null;
    return int.parse(value.substring(0, 4)) * 12 + int.parse(value.substring(5, 7));
  }

  static String _reference(Object? raw) {
    if (raw == null) return '平均月収の対象期間・入力元：保存記録なし';
    try {
      final ref = PayrollInsuranceBasisReference.fromJson(raw);
      final period = '${_eraMonth(ref.from)}〜${_eraMonth(ref.to)}';
      final amount = insuranceEvidenceMoney(ref.averageMonthlyIncomeYen);
      if (ref.source == 'manual') return '参考入力：手入力の平均月収 $amount（参照期間 $period）';
      if (ref.source == 'actual_complete') {
        return '参考記録：$period（対象${ref.observedMonths}か月）平均月収 $amount';
      }
      return '参考記録：$period のうち${ref.observedMonths}か月の実績平均 $amount（採用月一覧は未記録）';
    } on FormatException {
      return '平均月収の対象期間・入力元：保存記録を確認できません';
    }
  }

  static String _eraMonth(String month) {
    final year = int.parse(month.substring(0, 4));
    return '${year >= 2019 ? 'R${year - 2018}' : '$year'}.${int.parse(month.substring(5, 7))}';
  }
}

class PayrollInsuranceEvidenceRow {
  const PayrollInsuranceEvidenceRow(this.name, this.amountYen, this.formula);
  final String name, formula;
  final int amountYen;
}

int? insuranceEvidenceYen(Object? value) => value is num && value.isFinite &&
  value >= 0 && value <= 2147483647 && value == value.round() ? value.toInt() : null;

String insuranceEvidenceMoney(int value) => '¥${value.toString().replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')}';

String insuranceEvidencePercent(int scaled) {
  final whole = scaled ~/ 1000000;
  final fraction = (scaled % 1000000).toString().padLeft(6, '0').replaceFirst(RegExp(r'0+$'), '');
  return fraction.isEmpty ? '$whole' : '$whole.$fraction';
}


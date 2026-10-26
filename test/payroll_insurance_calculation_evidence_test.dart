import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/payroll_insurance_calculation_evidence.dart';

import 'fixtures/payroll_insurance_evidence_fixture.dart';

void main() {
  PayrollInsuranceCalculationEvidence read(Map<String, dynamic> detail) =>
      PayrollInsuranceCalculationEvidence.fromDetail(detail, month: '2026-10-01');
  test('uses each saved base/rate/amount and declares average only a reference', () {
    final detail = insuranceEvidenceFixture(); final before = jsonEncode(detail);
    final value = read(detail);
    expect(value.rows.map((r) => r.formula), contains('標準報酬月額 ¥320,000 × 4.925% ＝ ¥15,760'));
    expect(value.rows.map((r) => r.formula), contains('標準報酬月額 ¥340,000 × 9.15% ＝ ¥31,110'));
    expect(value.rows.map((r) => r.formula), contains('当月対象賃金 ¥340,000 × 0.5% ＝ ¥1,700'));
    expect(value.referenceText, contains('手入力の平均月収 ¥500,000'));
    expect(value.referenceText, contains('R8.4〜R8.6'));
    expect(value.referenceText, isNot(contains('初回')));
    expect(value.provenanceText, contains('採用関係は未記録'));
    expect(jsonEncode(detail), before);
  });
  test('formats recorded rates, never a hard-coded current health rate', () {
    final detail = insuranceEvidenceFixture(); final tax = detail['tax_calculation'] as Map;
    final health = (tax['rates'] as List).first as Map;
    (health['value'] as Map)['employee'] = 5000000;
    health['employee_yen'] = 16000; detail['健康保険料'] = 16000;
    expect(read(detail).rows.first.formula, '標準報酬月額 ¥320,000 × 5% ＝ ¥16,000');
    expect(insuranceEvidencePercent(0), '0');
    expect(insuranceEvidencePercent(1234567), '1.234567');
  });
  test('manual override is distinct from the original automatic amount', () {
    final detail = insuranceEvidenceFixture(); detail['健康保険料'] = 17000;
    (detail['tax_calculation'] as Map)['deduction_overrides'] = {'health_insurance': 17000};
    expect(read(detail).rows.first.formula,
      '標準報酬月額 ¥320,000 × 4.925% ＝ ¥15,760／手動修正後 ¥17,000');
    (detail['tax_calculation'] as Map).remove('deduction_overrides');
    expect(read(detail).rows.first.formula, contains('不一致'));
    expect(read(detail).rows.first.formula, isNot(contains('×')));
  });
  test('invalid, duplicate, future or wrong-insurance-month evidence is not relabeled', () {
    for (final mutation in ['duplicate', 'future', 'wrong-month', 'missing-base', 'negative-rate']) {
      final detail = insuranceEvidenceFixture(); final rates = (detail['tax_calculation'] as Map)['rates'] as List;
      final first = rates.first as Map;
      switch (mutation) {
        case 'duplicate': rates.add(Map<String, Object>.from(first)); break;
        case 'future': (first['value'] as Map)['payroll_month'] = '2026-12-01'; break;
        case 'wrong-month': first['insurance_month'] = '2026-09-01'; break;
        case 'missing-base': first.remove('base_yen'); break;
        case 'negative-rate': (first['value'] as Map)['employee'] = -1; break;
      }
      expect(read(detail).rows.first.formula, isNot(contains('×')), reason: mutation);
      expect(read(detail).rows.first.amountYen, 15760);
    }
  });
  test('missing is distinct from explicit zero and manual premiums', () {
    expect(read({}).isEmpty, true);
    expect(read({'健康保険料': 0}).rows.single.formula, contains('保存記録なし'));
    final detail = insuranceEvidenceFixture(); final tax = detail['tax_calculation'] as Map;
    final conditions = tax['conditions'] as Map;
    conditions['insurance_mode'] = 'manual';
    conditions['manual_insurance_premiums'] = {'health_insurance': 15760,
      'pension_insurance': 31110, 'nursing_insurance': 2592,
      'employment_insurance': 1700, 'child_support': 368};
    expect(read(detail).rows.first.formula, '本人負担月額を手入力 ＝ ¥15,760');
    conditions.remove('insurance_basis_reference');
    expect(read(detail).referenceText, contains('保存記録なし'));
    tax['blocked'] = true; expect(read(detail).rows, isEmpty);
  });
  test('available-history window does not fabricate an adopted month list or first payroll', () {
    final detail = insuranceEvidenceFixture(); final ref =
      ((detail['tax_calculation'] as Map)['conditions'] as Map)['insurance_basis_reference'] as Map;
    ref['source'] = 'actual_available'; ref['observed_months'] = 1;
    ref['history_fingerprint'] = List.filled(64, 'a').join();
    expect(read(detail).referenceText, contains('採用月一覧は未記録'));
    expect(read(detail).referenceText, isNot(contains('給与実績 ¥')));
    ref['source'] = 'actual_complete'; ref['observed_months'] = 3;
    expect(read(detail).referenceText, contains('R8.4〜R8.6（対象3か月）平均月収 ¥500,000'));
  });
  test('saved minimum and maximum insurance bases print their own actual formulas', () {
    for (final values in [
      (58000, 88000, '標準報酬月額 ¥58,000 × 5% ＝ ¥2,900',
        '標準報酬月額 ¥88,000 × 9.15% ＝ ¥8,052'),
      (1390000, 650000, '標準報酬月額 ¥1,390,000 × 5% ＝ ¥69,500',
        '標準報酬月額 ¥650,000 × 9.15% ＝ ¥59,475'),
    ]) {
      final detail = insuranceBoundaryEvidenceFixture(healthBase: values.$1, pensionBase: values.$2);
      final before = jsonEncode(detail);
      final evidence = read(detail);
      expect(evidence.rows.first.formula, values.$3);
      expect(evidence.rows[1].formula, values.$4);
      expect(evidence.referenceText, contains('手入力の平均月収 ¥500,000'));
      expect(evidence.provenanceText, contains('採用関係は未記録'));
      expect(jsonEncode(detail), before);
    }
  });
  test('displaying a later statement does not replace a saved historical rate', () {
    final historical = insuranceBoundaryEvidenceFixture(healthBase: 58000, pensionBase: 88000);
    final later = insuranceBoundaryEvidenceFixture(healthBase: 1390000, pensionBase: 650000,
      healthRate: 6000000, month: '2026-11-01');
    final before = jsonEncode(historical);
    expect(read(historical).rows.first.formula, '標準報酬月額 ¥58,000 × 5% ＝ ¥2,900');
    expect(PayrollInsuranceCalculationEvidence.fromDetail(later, month: '2026-11-01')
      .rows.first.formula, '標準報酬月額 ¥1,390,000 × 6% ＝ ¥83,400');
    expect(read(historical).rows.first.formula, '標準報酬月額 ¥58,000 × 5% ＝ ¥2,900');
    expect(jsonEncode(historical), before);
  });
  test('boundary override and missing saved inputs never become a fabricated equation', () {
    final detail = insuranceBoundaryEvidenceFixture(healthBase: 58000, pensionBase: 88000);
    detail['健康保険料'] = 3000;
    final tax = detail['tax_calculation'] as Map;
    tax['deduction_overrides'] = {'health_insurance': 3000};
    expect(read(detail).rows.first.formula,
      '標準報酬月額 ¥58,000 × 5% ＝ ¥2,900／手動修正後 ¥3,000');
    tax.remove('deduction_overrides');
    expect(read(detail).rows.first.formula, isNot(contains('×')));
    expect(read(detail).rows.first.formula, contains('不一致'));
    final rate = (tax['rates'] as List).first as Map;
    rate.remove('base_yen');
    expect(read(detail).rows.first.formula, isNot(contains('×')));
    expect(read(detail).rows.first.amountYen, 3000);
    detail.remove('tax_calculation');
    expect(read(detail).rows.first.formula, contains('計算根拠の保存記録なし'));
    expect(read(detail).rows.first.formula, isNot(contains('×')));
  });

  test('legacy saved zero basis is not replaced by a new minimum on display', () {
    final detail = insuranceBoundaryEvidenceFixture(healthBase: 0, pensionBase: 0);
    final before = jsonEncode(detail);
    final evidence = read(detail);
    expect(evidence.rows.first.formula, '計算対象額 ¥0 × 5% ＝ ¥0');
    expect(evidence.rows[1].formula, '計算対象額 ¥0 × 9.15% ＝ ¥0');
    expect(evidence.rows.first.formula, isNot(contains('58,000')));
    expect(evidence.rows[1].formula, isNot(contains('88,000')));
    expect(jsonEncode(detail), before);
  });

  test('broken saved arithmetic never prints a false equation even when amounts agree', () {
    final detail = insuranceBoundaryEvidenceFixture(healthBase: 58000, pensionBase: 88000);
    final tax = detail['tax_calculation'] as Map;
    final health = (tax['rates'] as List).first as Map;
    health['employee_yen'] = 999999;
    (tax['premiums'] as Map)['健康保険料'] = 999999;
    detail['健康保険料'] = 999999;
    final before = jsonEncode(detail);
    final row = read(detail).rows.first;
    expect(row.amountYen, 999999);
    expect(row.formula, '控除額 ¥999,999（保存された計算基準・料率と不一致）');
    expect(row.formula, isNot(contains('×')));
    expect(row.formula, isNot(contains('＝')));
    expect(jsonEncode(detail), before);
    detail['健康保険料'] = 3000;
    tax['deduction_overrides'] = {'health_insurance': 3000};
    expect(read(detail).rows.first.amountYen, 3000);
    expect(read(detail).rows.first.formula, contains('保存された計算基準・料率と不一致'));
    expect(read(detail).rows.first.formula, isNot(contains('×')));
  });
  test('saved floor and ceiling both retain actual after-rounding amounts', () {
    for (final amount in [2856, 2857]) {
      final detail = insuranceBoundaryEvidenceFixture(healthBase: 58000,
        pensionBase: 88000, healthRate: 4925000);
      final tax = detail['tax_calculation'] as Map;
      ((tax['rates'] as List).first as Map)['employee_yen'] = amount;
      (tax['premiums'] as Map)['健康保険料'] = amount;
      detail['健康保険料'] = amount;
      final before = jsonEncode(detail);
      expect(read(detail).rows.first.formula,
        amount == 2856 ? '標準報酬月額 ¥58,000 × 4.925% ＝ ¥2,856'
          : '標準報酬月額 ¥58,000 × 4.925% ＝ ¥2,857');
      expect(jsonEncode(detail), before);
    }
  });
  test('integer evidence guard remains exact beyond double safe multiplication', () {
    for (final amount in [2147483625, 2147483626]) {
      final detail = insuranceBoundaryEvidenceFixture(healthBase: 58000, pensionBase: 88000);
      final tax = detail['tax_calculation'] as Map;
      final health = (tax['rates'] as List).first as Map;
      health['base_yen'] = 2147483647;
      (health['value'] as Map)['employee'] = 99999999;
      health['employee_yen'] = amount;
      detail['健康保険料'] = amount;
      expect(read(detail).rows.first.amountYen, amount);
      expect(read(detail).rows.first.formula, contains('× 99.999999% ＝'));
      health['employee_yen'] = amount + 2;
      detail['健康保険料'] = amount + 2;
      expect(read(detail).rows.first.formula, contains('保存された計算基準・料率と不一致'));
      expect(read(detail).rows.first.formula, isNot(contains('×')));
    }
  });

}

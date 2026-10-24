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
}

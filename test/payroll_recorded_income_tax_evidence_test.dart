import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/payroll_recorded_income_tax_evidence.dart';

void main() {
  Map<String, dynamic> saved() => {'所得税': 7020, 'tax_calculation': {
    'calculator_version': 'payroll-tax-20261014-overrides-v1',
    'condition_version': 1, 'conditions_start': '2026-01-01',
    'payment_date': '2026-10-25', 'income_table': 'nta-monthly-2026-c583c9c3',
    'gross_with_adjustments': 420000, 'social_yen': 63400,
    'income_tax_base_yen': 356600, 'income_tax_yen': 7020,
    'automatic_income_tax_yen': 7020, 'deduction_overrides': <String, dynamic>{},
    'conditions': {'income_mode': 'koh', 'dependents': 2,
      'non_taxable_yen': 0, 'additional_social_deduction_yen': 0},
  }};
  String read(Map<String, dynamic> detail, {num amount = 7020}) =>
      recordedPayrollIncomeTaxExplanation(detail, month: '2026-09-01', displayedAmount: amount);
  test('saved taxable base and table are displayed without recalculating money', () {
    final detail = saved(), before = jsonEncode(saved());
    expect(read(detail), '対象356,600円／R8月額表 甲欄・扶養2人');
    expect(jsonEncode(detail), before);
    final tax = detail['tax_calculation'] as Map;
    (tax['conditions'] as Map)['income_mode'] = 'otsu';
    expect(read(detail), endsWith('乙欄'));
    expect(read(detail), isNot(contains('扶養')));
  });
  test('complete saved basis exposes the actual subtraction and table lookup', () {
    final detail = saved();
    final before = jsonEncode(detail);
    final result = recordedPayrollIncomeTaxEvidence(detail, month: '2026-09-01', displayedAmount: 7020);
    expect(result.calculationLines, [
      '所得税対象額：支給額 420,000円 − 非課税額 0円 − 社会保険料等 63,400円 − 他項目で控除済みの社会保険料等 0円 ＝ 356,600円',
      '令和8年月額表：甲欄・扶養2人、対象 356,600円 → 自動計算 7,020円',
    ]);
    expect(jsonEncode(detail), before);
    final tax = detail['tax_calculation'] as Map;
    tax['income_tax_yen'] = 8000;
    tax['deduction_overrides'] = {'income_tax': 8000};
    expect(recordedPayrollIncomeTaxEvidence(detail, month: '2026-09-01', displayedAmount: 8000)
        .calculationLines.last, endsWith('自動計算 7,020円／手動修正後 8,000円'));
    (tax['conditions'] as Map)['income_mode'] = 'otsu';
    expect(recordedPayrollIncomeTaxEvidence(detail, month: '2026-09-01', displayedAmount: 8000)
        .calculationLines.last, contains('乙欄・従たる給与の申告扶養2人'));
  });
  test('personal UID producer preserves saved income evidence and never needs raw DOB', () {
    final detail=saved();
    final expected=recordedPayrollIncomeTaxEvidence(detail,month:'2026-09-01',displayedAmount:7020);
    final tax=detail['tax_calculation'] as Map;
    tax['calculator_version']='payroll-tax-personal-uid-v1';
    tax['personal_details_basis']={'source_kind':'personal_uid_v1','revision':2,'binding_sha256':'a'*64};
    final before=jsonEncode(detail);
    final actual=recordedPayrollIncomeTaxEvidence(detail,month:'2026-09-01',displayedAmount:7020);
    expect(actual.summary,expected.summary);expect(actual.calculationLines,expected.calculationLines);
    expect(jsonEncode(detail),before);expect((tax['conditions'] as Map).containsKey('birth_date'),false);
  });
  test('missing saved operands never invent an actual formula', () {
    for (final key in ['gross_with_adjustments', 'social_yen', 'income_tax_base_yen']) {
      final detail = saved();
      (detail['tax_calculation'] as Map).remove(key);
      expect(recordedPayrollIncomeTaxEvidence(detail, month: '2026-09-01', displayedAmount: 7020)
          .calculationLines, isEmpty);
    }
    final detail = saved();
    ((detail['tax_calculation'] as Map)['conditions'] as Map).remove('non_taxable_yen');
    expect(recordedPayrollIncomeTaxEvidence(detail, month: '2026-09-01', displayedAmount: 7020)
        .calculationLines, isEmpty);
  });
  test('explicit fixed and override values are distinguished from automatic results', () {
    final detail = saved();
    final tax = detail['tax_calculation'] as Map;
    tax['income_tax_yen'] = 8000;
    tax['deduction_overrides'] = {'income_tax': 8000};
    expect(read(detail, amount: 8000), endsWith('・手動修正'));
    (tax['conditions'] as Map)['income_mode'] = 'fixed';
    expect(read(detail, amount: 8000), '手動修正（保存額）');
    tax['deduction_overrides'] = <String, dynamic>{};
    expect(read(detail, amount: 8000), '固定額の計算根拠は未記録');
  });
  test('a saved amount mismatch and false arithmetic do not print an authoritative basis', () {
    expect(read(saved(), amount: 8000), '保存された所得税額と不一致');
    final detail = saved();
    (detail['tax_calculation'] as Map)['income_tax_base_yen'] = 356601;
    expect(read(detail), '保存された課税対象額と不一致');
    (detail['tax_calculation'] as Map)['blocked'] = true;
    expect(read(detail), '計算根拠の保存記録なし');
  });
  test('missing records, unknown producers, impossible dates and invalid conditions stay unknown', () {
    expect(read({'所得税': 7020}), '計算根拠の保存記録なし');
    for (final edit in [
      {'calculator_version': 'future'}, {'condition_version': 0},
      {'conditions_start': '2026-11-01'}, {'payment_date': '2027-01-25'},
      {'payment_date': '2026-02-31'}, {'income_table': 'unknown'},
      {'automatic_income_tax_yen': 9999},
    ]) {
      final detail = saved();
      (detail['tax_calculation'] as Map).addAll(edit);
      expect(read(detail), '計算根拠の保存記録なし', reason: edit.toString());
    }
  });
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/payroll_recorded_tax_amounts.dart';

void main() {
  Map<String, dynamic> calculated() => {
    'tax_calculation': <String, dynamic>{
      'calculator_version': 'payroll-tax-20261010-v1',
      'condition_version': 1, 'conditions_start': '2026-09-01',
      'conditions': {'insurance_mode': 'rates'},
      'premiums': {'健康保険料': 15000, '厚生年金保険': 27450, '介護保険料': 0},
    },
    '所得税': 6220, '住民税': 12000,
  };

  test('reads persisted producer premiums when named display fields are absent without mutating data', () {
    final detail = calculated();
    final before = jsonEncode(detail);
    final linked = detailWithRecordedPayrollInsurance(detail, month: '2026-09-01');
    expect(linked['健康保険料'], 15000);
    expect(linked['厚生年金保険'], 27450);
    expect(linked['介護保険料'], 0);
    expect(linked['所得税'], 6220);
    expect(linked['住民税'], 12000);
    expect(jsonEncode(detail), before);
  });

  test('explicit scalar zero and invalid scalar are never replaced by a snapshot', () {
    final detail = calculated();
    detail['健康保険料'] = 0;
    detail['厚生年金保険'] = 'invalid';
    final linked = detailWithRecordedPayrollInsurance(detail, month: '2026-09-01');
    expect(linked['健康保険料'], 0);
    expect(linked['厚生年金保険'], 'invalid');
  });

  test('blocked, future, unknown and malformed calculations provide no display fallback', () {
    for (final change in <Map<String, dynamic>>[
      {'blocked': true}, {'conditions_start': '2026-10-01'},
      {'calculator_version': 'unknown'}, {'condition_version': 0},
      {'premiums': {'健康保険料': '15000', '厚生年金保険': -1}},
      {'conditions': {'insurance_mode': 'fixed'}},
    ]) {
      final detail = calculated();
      (detail['tax_calculation'] as Map).addAll(change);
      expect(recordedPayrollInsuranceAmounts(detail, month: '2026-09-01'), isEmpty);
    }
  });
}

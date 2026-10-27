import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/payroll_recorded_unit_evidence.dart';

void main() {
  Map<String, dynamic> saved() => {'unit_resolution': {
    'contract_version': 1, 'blocked': false, 'items': [
      {'id': 'individual-unused', 'name': '合成共通手当', 'section': 'earning',
       'unit': 'day', 'rate_yen': 800, 'quantity': 0, 'amount_yen': 0},
      {'id': 'common-used', 'name': '合成共通手当', 'section': 'earning',
       'origin': 'company_common', 'unit': 'day', 'rate_yen': 1200,
       'quantity': 3, 'amount_yen': 3600},
    ],
  }};
  PayrollRecordedUnitEvidence? read(Map<String, dynamic> detail, {num amount = 3600}) =>
      recordedPayrollUnitEvidence(detail, name: '合成共通手当',
          section: 'earning', displayedAmount: amount);

  test('unused same-name row does not hide the exact saved common price and days', () {
    final detail = saved(), before = jsonEncode(saved());
    expect(read(detail)?.calculation, '1,200円 × 3日');
    expect(read(detail)?.quantityLabel, '3日');
    expect(jsonEncode(detail), before);
    expect(read(detail, amount: 4800), isNull);
  });
  test('two paid same-name items still cannot borrow one basis', () {
    final detail = saved();
    final unused = ((detail['unit_resolution'] as Map)['items'] as List).first as Map;
    unused.addAll({'quantity': 1, 'amount_yen': 800});
    expect(read(detail, amount: 4400), isNull);
    expect(read(detail), isNull);
  });
  test('invalid zero evidence is not silently ignored', () {
    for (final invalid in [
      {'rate_yen': -1}, {'rate_yen': double.nan}, {'unit': 'unknown'},
      {'quantity': 1}, {'amount_yen': 1}, {'quantity': null},
    ]) {
      final detail = saved();
      (((detail['unit_resolution'] as Map)['items'] as List).first as Map).addAll(invalid);
      expect(read(detail), isNull, reason: invalid.toString());
    }
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/payroll_recorded_unit_evidence.dart';

Map<String, dynamic> detail() => {
  'unit_resolution': <String, dynamic>{
    'contract_version': 1, 'blocked': false,
    'items': <Map<String, dynamic>>[
      <String, dynamic>{'id': 'saved-hour', 'name': '時間手当', 'section': 'earning',
       'unit': 'hour', 'quantity': 7.25, 'rate_yen': 1000, 'amount_yen': 7250},
    ],
  },
};

PayrollRecordedUnitEvidence? evidence(Map<String, dynamic> saved,
    {String section = 'earning', num amount = 7250}) =>
  recordedPayrollUnitEvidence(saved, name: '時間手当', section: section, displayedAmount: amount);

void main() {
  test('attendance evidence prints saved base and allowance day counts, never whole-month days', () {
    final saved = <String, dynamic>{
      '出勤日数': 17,
      'attendance_unit_evidence': {
        'contract_version': 1, 'blocked': false,
        'items': [
          {'name': '基本給', 'section': 'earning', 'unit': 'day',
           'quantity': 17, 'rate_yen': 16000, 'amount_yen': 272000},
          {'name': '合成手当', 'section': 'earning', 'unit': 'day',
           'quantity': 3, 'rate_yen': 700, 'amount_yen': 2100},
        ],
      },
    };
    final base = recordedPayrollUnitEvidence(saved, name: '基本給', section: 'earning',
      displayedAmount: 272000);
    expect(base?.calculation, '16,000円 × 17日');
    final allowance = recordedPayrollUnitEvidence(saved, name: '合成手当', section: 'earning',
      displayedAmount: 2100);
    expect(allowance?.quantityLabel, '3日');
    expect(allowance?.calculation, '700円 × 3日');
    expect(recordedPayrollUnitEvidence(saved, name: '合成手当', section: 'earning',
      displayedAmount: 2800), isNull);
    expect(recordedPayrollUnitEvidence({'出勤日数': 17, '基本給': 272000,
      'payroll_settings': {'day_daily': 16000}}, name: '基本給',
      section: 'earning', displayedAmount: 272000), isNull);
  });
  test('ambiguous or blocked primary evidence never borrows attendance fallback', () {
    final saved = detail();
    saved['attendance_unit_evidence'] = {
      'contract_version': 1, 'items': [
        {'name': '時間手当', 'section': 'earning', 'unit': 'day',
         'quantity': 5, 'rate_yen': 1450, 'amount_yen': 7250},
      ],
    };
    (saved['unit_resolution'] as Map)['blocked'] = true;
    expect(evidence(saved), isNull);
    (saved['unit_resolution'] as Map)['items'] = [];
    expect(evidence(saved), isNull);
  });
  test('categories preserve saved rates and reject overrides and rounding ambiguity', () {
    final saved = <String, dynamic>{'attendance_unit_evidence': {
      'contract_version': 1, 'items': [
        {'name': '基本給', 'section': 'earning', 'unit': 'day', 'category': 'day',
         'rate_yen': 16000, 'quantity': 1, 'amount_yen': 16000},
        {'name': '基本給', 'section': 'earning', 'unit': 'day', 'category': 'night',
         'rate_yen': 18000, 'quantity': 0.5, 'amount_yen': 9000},
      ],
    }};
    PayrollRecordedUnitEvidence? read(num amount) => recordedPayrollUnitEvidence(
      saved, name: '基本給', section: 'earning', displayedAmount: amount);
    expect(read(25000)?.quantityLabel, '1.5日');
    expect(read(25000)?.calculation, '日勤 16,000円 × 1日／夜勤 18,000円 × 0.5日');
    expect(read(26000), isNull);
    (((saved['attendance_unit_evidence'] as Map)['items'] as List).first as Map)['amount_yen'] = 16001;
    expect(read(25001), isNull);
  });
  test('saved quantity and price explain the exact printed amount', () {
    final saved = detail();
    saved['current_rate_yen'] = 99999;
    expect(evidence(saved)?.quantityLabel, '7.25時間');
    expect(evidence(saved)?.calculation, '1,000円 × 7.25時間');
    expect((saved['unit_resolution'] as Map)['items'][0]['amount_yen'], 7250);
  });
  test('deduction rows cannot borrow an equal-name earning basis', () {
    expect(evidence(detail(), section: 'deduction'), isNull);
  });
  test('combined or adjusted displayed money is not falsely explained', () {
    expect(evidence(detail(), amount: 8250), isNull);
    final duplicate = detail();
    final items = (duplicate['unit_resolution'] as Map)['items'] as List;
    items.add({...Map<String, dynamic>.from(items.first as Map), 'id': 'other-item'});
    expect(evidence(duplicate, amount: 14500), isNull);
  });
  test('unknown, blocked and nonfinite saved evidence stays unavailable', () {
    expect(evidence({}), isNull);
    for (final edit in <Map<String, dynamic>>[
      {'quantity': null}, {'quantity': double.nan}, {'rate_yen': double.infinity},
      {'amount_yen': 7251}, {'quantity': -7.25}, {'unit': 'unknown'},
      {'rate_yen': 1e308, 'quantity': 1e308},
    ]) {
      final saved = detail();
      ((saved['unit_resolution'] as Map)['items'][0] as Map).addAll(edit);
      expect(evidence(saved), isNull);
    }
    final saved = detail();
    (saved['unit_resolution'] as Map)['blocked'] = true;
    expect(evidence(saved), isNull);
  });
}


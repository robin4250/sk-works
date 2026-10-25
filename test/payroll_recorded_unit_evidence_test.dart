import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/payroll_recorded_unit_evidence.dart';

Map<String, dynamic> detail() => {
  'unit_resolution': {
    'contract_version': 1, 'blocked': false,
    'items': [
      {'id': 'saved-hour', 'name': '時間手当', 'section': 'earning',
       'unit': 'hour', 'quantity': 7.25, 'rate_yen': 1000, 'amount_yen': 7250},
    ],
  },
};

PayrollRecordedUnitEvidence? evidence(Map<String, dynamic> saved,
    {String section = 'earning', num amount = 7250}) =>
  recordedPayrollUnitEvidence(saved, name: '時間手当', section: section, displayedAmount: amount);

void main() {
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

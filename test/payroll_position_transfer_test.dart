import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/payroll_position_transfer.dart';

void main() {
  Map<String, dynamic> detail({bool enabled = true, String payType = 'daily', num days = 20}) => {
    'position_transfer_snapshot': {'version': 1, 'enabled': enabled,
      'pay_type': payType, 'items': [{'name': '役職手当', 'amount_yen': 11000},
        {'name': '勤務手当', 'amount_yen': 5000}]},
    'attendance_unit_evidence': {'contract_version': 1, 'items': [
      {'name': '基本給', 'section': 'earning', 'category': 'day', 'unit': 'day',
       'rate_yen': 10000, 'quantity': days, 'amount_yen': 200000},
    ]},
  };
  final original = <String, Object?>{'基本給': 200000, '役職手当': 11000,
    '勤務手当': 5000, '残業手当': 25000};
  test('half up to 500 and signed difference keep original total', () {
    final v = payrollPositionTransfer(detail(), original)!;
    expect(v.rate, 11000);
    expect(v.entries['基本給'], 220000);
    expect(v.entries['基本給の調整額'], -4000);
    expect(v.entries['残業手当'], 25000);
    expect(v.entries.values.cast<num>().reduce((a, b) => a + b),
      original.values.cast<num>().reduce((a, b) => a + b));
    expect(original['役職手当'], 11000);
  });
  test('disabled, non-daily, zero days and unrecorded basis are unchanged', () {
    expect(payrollPositionTransfer(detail(enabled: false), original), isNull);
    expect(payrollPositionTransfer(detail(payType: 'monthly'), original), isNull);
    expect(payrollPositionTransfer(detail(days: 0), original), isNull);
    expect(payrollPositionTransfer({}, original), isNull);
  });
  test('mismatched allowance amounts and combined base rates fail closed', () {
    expect(payrollPositionTransfer(detail(), {...original, '役職手当': 9000}), isNull);
    final duplicate = detail();
    (duplicate['position_transfer_snapshot']['items'] as List).add(
      {'name': '役職手当', 'amount_yen': 11000});
    expect(payrollPositionTransfer(duplicate, original), isNull);
    final d = detail();
    (d['attendance_unit_evidence']['items'] as List).add({
      'name': '基本給', 'section': 'earning', 'unit': 'day', 'category': 'night',
      'rate_yen': 15000, 'quantity': 1, 'amount_yen': 15000});
    expect(payrollPositionTransfer(d, original), isNull);
  });
}

import 'package:flutter_test/flutter_test.dart';
import '../lib/features/payroll/paid_leave_pay.dart';

void main() {
  test('daily paid leave uses exactly one registered daily wage per day', () {
    final pay = PaidLeavePay.fromSettings({'day_daily': 12000});
    expect(pay.additionalWagesForDays(2), 24000);
  });
  test('hourly default is eight hours independently of working-day formula', () {
    final pay = PaidLeavePay.fromSettings({
      'pay_type': 'hourly', 'hourly_rate_yen': 1500,
      'rate_formula': {'hours_per_day': 6},
    });
    expect(pay.dailyAmountYen, 12000);
  });
  test('hourly explicit override including zero remains authoritative', () {
    for (final amount in [0, 9000]) {
      final pay = PaidLeavePay.fromSettings({
        'pay_type': 'hourly', 'hourly_rate_yen': 1500,
        'rate_formula': {'paid_leave_daily_yen': amount},
      });
      expect(pay.additionalWagesForDays(1), amount);
    }
  });
  test('monthly daily amount is an allocation and never extra monthly wages', () {
    final pay = PaidLeavePay.fromSettings({
      'pay_type': 'monthly', 'monthly_salary_yen': 300000,
      'calculation_daily_base_yen': 14000,
    });
    expect(pay.dailyAmountYen, 14000);
    expect(pay.additionalWagesForDays(3), 0);
  });
  test('negative day counts are rejected', () {
    final pay = PaidLeavePay.fromSettings({'day_daily': 12000});
    expect(() => pay.additionalWagesForDays(-1), throwsArgumentError);
  });
}

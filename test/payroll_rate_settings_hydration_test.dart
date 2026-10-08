import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/domain/payroll_rate_settings_hydration.dart';

void main() {
  test('legacy daily rates preserve manual differences without mutating source', () {
    final stored = <String, dynamic>{
      'pay_type': 'daily', 'day_daily': 8000,
      'day_overtime': 1800, 'day_early': 1250, 'night_daily': 13000,
    };
    final hydrated = hydratePayrollRateSettings(stored);
    expect(hydrated['rate_overrides'], {'overtime': 1800, 'night': 13000});
    expect(stored.containsKey('rate_overrides'), isFalse);
  });

  test('hourly basis uses registered hourly amount rather than daily amount', () {
    final hydrated = hydratePayrollRateSettings({
      'pay_type': 'hourly', 'day_daily': 8000, 'hourly_rate_yen': 1000,
      'day_overtime': 1250, 'night_daily': 12500,
    });
    expect(hydrated['rate_overrides'], {'night': 12500});
    expect((hydrated['rate_formula'] as Map)['hourly_rate_yen'], 1000);
    expect((hydrated['rate_formula'] as Map)['hourly_base'], isTrue);
  });

  test('monthly uses calculation daily base and registered multipliers', () {
    final hydrated = hydratePayrollRateSettings({
      'pay_type': 'monthly', 'monthly_salary_yen': 300000,
      'calculation_daily_base_yen': 10000, 'day_daily': 8000,
      'rate_formula': {'hours_per_day': 10, 'overtime_multiplier': 1.4},
      'day_overtime': 1400, 'night_daily': 15500,
    });
    expect(hydrated['rate_overrides'], {'night': 15500});
  });

  test('schema-default empty overrides restores registered manual amounts', () {
    expect(hydratePayrollRateSettings({
      'day_daily': 8000, 'day_overtime': 1800, 'rate_overrides': <String, int>{},
    })['rate_overrides'], {'overtime': 1800});
  });

  test('nonempty overrides remain authoritative', () {
    expect(hydratePayrollRateSettings({
      'day_daily': 8000, 'day_overtime': 1800,
      'rate_overrides': {'overtime': 0, 'night': 14000},
    })['rate_overrides'], {'overtime': 0, 'night': 14000});
  });

  test('empty overrides with formula-matching rates stays automatic', () {
    expect(hydratePayrollRateSettings({
      'day_daily': 8000, 'day_overtime': 1250,
      'rate_overrides': <String, int>{},
    })['rate_overrides'], isEmpty);
  });

  test('unrelated save keeps legacy zero and unsupported early rates', () {
    final values = <String, dynamic>{'day_overtime': 1250, 'night_early': 1875};
    preserveUnchangedPayrollRates(values,
      {'day_overtime': 0, 'night_early': 2100}, unchanged: true);
    expect(values, {'day_overtime': 0, 'night_early': 2100});
    preserveUnchangedPayrollRates(values,
      {'day_overtime': 9000}, unchanged: false);
    expect(values['day_overtime'], 0);
  });
}

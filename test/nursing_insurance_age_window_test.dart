import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/domain/company_rate_contract.dart';
import 'package:sk_works/features/payroll/domain/nursing_insurance_age_window.dart';

void main() {
  test('ordinary birthday includes attaining 40 month, excludes attaining 65 month', () {
    final window = NursingInsuranceAgeWindow(PayrollDate(1986, 5, 2));
    expect(window.startsOnMonth, RateMonth(2026, 5));
    expect(window.endsBeforeMonth, RateMonth(2051, 5));
    expect(window.includesInsuranceMonth(RateMonth(2026, 4)), isFalse);
    expect(window.includesInsuranceMonth(RateMonth(2026, 5)), isTrue);
    expect(window.includesInsuranceMonth(RateMonth(2051, 4)), isTrue);
    expect(window.includesInsuranceMonth(RateMonth(2051, 5)), isFalse);
  });

  test('first-day birthday shifts both boundaries to previous insured month', () {
    final window = NursingInsuranceAgeWindow(PayrollDate(1986, 5, 1));
    expect(window.startsOnMonth, RateMonth(2026, 4));
    expect(window.endsBeforeMonth, RateMonth(2051, 4));
    expect(window.includesInsuranceMonth(RateMonth(2026, 3)), isFalse);
    expect(window.includesInsuranceMonth(RateMonth(2026, 4)), isTrue);
    expect(window.includesInsuranceMonth(RateMonth(2051, 3)), isTrue);
    expect(window.includesInsuranceMonth(RateMonth(2051, 4)), isFalse);
  });

  test('January first crosses year without timezone or current-day dependence', () {
    final window = NursingInsuranceAgeWindow(PayrollDate(1987, 1, 1));
    expect(window.startsOnMonth, RateMonth(2026, 12));
    expect(window.endsBeforeMonth, RateMonth(2051, 12));
    expect(window.includesInsuranceMonth(RateMonth(2027, 1)), isTrue);
    expect(window.includesInsuranceMonth(RateMonth(2052, 1)), isFalse);
  });

  test('leap-day birth remains a February insured-month boundary', () {
    final window = NursingInsuranceAgeWindow(PayrollDate(1988, 2, 29));
    expect(window.startsOnMonth, RateMonth(2028, 2));
    expect(window.endsBeforeMonth, RateMonth(2053, 2));
    expect(window.includesInsuranceMonth(RateMonth(2053, 1)), isTrue);
    expect(window.includesInsuranceMonth(RateMonth(2053, 2)), isFalse);
  });
}

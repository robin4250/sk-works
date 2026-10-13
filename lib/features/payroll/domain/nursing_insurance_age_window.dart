import 'company_rate_contract.dart';

/// Age-only window for insured months, not payroll deduction/payment months.
/// Coverage, exemptions and insurer-specific rules must be checked separately.
class NursingInsuranceAgeWindow {
  NursingInsuranceAgeWindow(PayrollDate birthDate)
      : startsOnMonth = _attainmentMonth(birthDate, 40),
        endsBeforeMonth = _attainmentMonth(birthDate, 65);

  final RateMonth startsOnMonth;
  final RateMonth endsBeforeMonth;

  bool includesInsuranceMonth(RateMonth insuranceMonth) =>
      _compare(insuranceMonth, startsOnMonth) >= 0 &&
      _compare(insuranceMonth, endsBeforeMonth) < 0;

  static RateMonth _attainmentMonth(PayrollDate birthDate, int age) {
    // Age is attained the day before the birthday. A first-day birthday
    // therefore moves the insured-month boundary to the preceding month.
    if (birthDate.day != 1) {
      return RateMonth(birthDate.year + age, birthDate.month);
    }
    if (birthDate.month == 1) {
      return RateMonth(birthDate.year + age - 1, 12);
    }
    return RateMonth(birthDate.year + age, birthDate.month - 1);
  }

  static int _compare(RateMonth left, RateMonth right) =>
      (left.year * 12 + left.month).compareTo(right.year * 12 + right.month);
}

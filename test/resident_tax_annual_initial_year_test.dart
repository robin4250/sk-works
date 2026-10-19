import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/settings/company_payroll_rates_page.dart';
void main() {
  test('JST calendar new year retains the preceding June-start tax year', () {
    expect(residentTaxAnnualInitialYear(DateTime.parse('2026-12-31T14:59:59Z')), 2026);
    expect(residentTaxAnnualInitialYear(DateTime.parse('2026-12-31T15:00:00Z')), 2026);
    expect(residentTaxAnnualInitialYear(DateTime.parse('2027-04-01T00:00:00+09:00')), 2026);
  });
  test('May 1 JST switches directly into preparation for the coming June', () {
    expect(residentTaxAnnualInitialYear(DateTime.parse('2026-04-30T14:59:59Z')), 2025);
    expect(residentTaxAnnualInitialYear(DateTime.parse('2026-04-30T15:00:00Z')), 2026);
    expect(residentTaxAnnualInitialYear(DateTime.parse('2026-05-01T00:00:00+09:00')), 2026);
    expect(residentTaxAnnualInitialYear(DateTime.parse('2026-06-01T00:00:00+09:00')), 2026);
  });
}

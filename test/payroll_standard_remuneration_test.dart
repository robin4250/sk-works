import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/payroll_standard_remuneration.dart';

void main() {
  test('every official health boundary is inclusive, preceding yen remains previous grade', () {
    final lows = PayrollStandardRemuneration.lowerBounds;
    final bases = PayrollStandardRemuneration.healthBases;
    expect(lows.length, 50);
    expect(bases.length, 50);
    for (var i = 1; i < lows.length; i++) {
      expect(PayrollStandardRemuneration.fromMonthlyIncome(lows[i], '2026-10').healthYen,
          bases[i], reason: 'lower boundary $i');
      expect(PayrollStandardRemuneration.fromMonthlyIncome(lows[i] + 1, '2026-10').healthYen,
          bases[i], reason: 'next yen $i');
      expect(PayrollStandardRemuneration.fromMonthlyIncome(lows[i] - 1, '2026-10').healthYen,
          bases[i - 1], reason: 'previous yen $i');
    }
  });
  test('health and pension independently enforce their different floors and ceilings', () {
    final low = PayrollStandardRemuneration.fromMonthlyIncome(1, '2026-01');
    expect(low.healthYen, 58000); expect(low.pensionYen, 88000);
    final high = PayrollStandardRemuneration.fromMonthlyIncome(2147483647, '2026-12');
    expect(high.healthYen, 1390000); expect(high.pensionYen, 650000);
    expect(PayrollStandardRemuneration.fromMonthlyIncome(635000, '2026-10').pensionYen, 650000);
    expect(PayrollStandardRemuneration.fromMonthlyIncome(665000, '2026-10').healthYen, 680000);
    expect(PayrollStandardRemuneration.fromMonthlyIncome(665000, '2026-10').pensionYen, 650000);
  });
  test('zero, negative, overflow, malformed and unsupported years refuse conversion', () {
    for (final value in [0, -1, 2147483648]) {
      expect(() => PayrollStandardRemuneration.fromMonthlyIncome(value, '2026-10'), throwsFormatException);
    }
    for (final month in ['2025-12', '2027-01', '2026-13', '2026-1', '2026-10-01']) {
      expect(() => PayrollStandardRemuneration.fromMonthlyIncome(300000, month), throwsFormatException);
    }
  });
}

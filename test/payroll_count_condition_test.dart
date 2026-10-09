import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/domain/payroll_count_condition.dart';
import 'package:sk_works/features/payroll/domain/payroll_item_condition.dart';

void main() {
  PayrollCountCondition condition(int yen, PayrollItemRounding rounding) =>
      PayrollCountCondition(unitAmountYen: yen, rounding: rounding);
  int calculate(int yen, String count, PayrollItemRounding rounding) =>
      condition(yen, rounding)
          .calculate(count: PayrollItemQuantity.parse(count)).amountYen;

  test('one and two occurrences use the same registered unit price', () {
    expect(calculate(700, '1', PayrollItemRounding.down), 700);
    expect(calculate(700, '2', PayrollItemRounding.down), 1400);
    expect(calculate(1234, '1.25', PayrollItemRounding.nearestHalfUp), 1543);
  });

  test('exact four-place counts honor the explicitly chosen rounding', () {
    expect(calculate(3, '0.5', PayrollItemRounding.down), 1);
    expect(calculate(3, '0.5', PayrollItemRounding.up), 2);
    expect(calculate(3, '0.5', PayrollItemRounding.nearestHalfUp), 2);
    expect(calculate(1, '0.4999', PayrollItemRounding.nearestHalfUp), 0);
    expect(calculate(1, '0.5000', PayrollItemRounding.nearestHalfUp), 1);
    expect(calculate(1, '0.0001', PayrollItemRounding.up), 1);
    expect(calculate(1, '0.0001', PayrollItemRounding.down), 0);
  });

  test('zero count or zero price suppresses only the calculated display', () {
    final zeroCount = condition(700, PayrollItemRounding.up)
        .calculate(count: PayrollItemQuantity.parse('0'));
    expect(zeroCount.amountYen, 0);
    expect(zeroCount.shouldDisplayOnStatement, isFalse);
    expect(condition(0, PayrollItemRounding.down)
        .calculate(count: PayrollItemQuantity.parse('2'))
        .shouldDisplayOnStatement, isFalse);
    expect(condition(1, PayrollItemRounding.down)
        .calculate(count: PayrollItemQuantity.parse('1'))
        .shouldDisplayOnStatement, isTrue);
  });

  test('malformed counts reject instead of silently becoming zero', () {
    for (final input in [
      '-1', 'NaN', 'Infinity', '1e3', '1.00001', '.5', '1.', ' 1', '',
    ]) {
      expect(() => PayrollItemQuantity.parse(input), throwsFormatException);
    }
    expect(() => PayrollItemQuantity.parse('900719925474.0992'),
        throwsRangeError);
    expect(() => condition(-1, PayrollItemRounding.down), throwsRangeError);
    expect(() => condition(PayrollItemCondition.maxExactInteger + 1,
        PayrollItemRounding.down), throwsRangeError);
  });

  test('exact result limit is accepted and overflow rejects before int conversion', () {
    final max = PayrollItemCondition.maxExactInteger;
    expect(calculate(max, '1', PayrollItemRounding.down), max);
    expect(() => calculate(max, '2', PayrollItemRounding.down), throwsRangeError);
    expect(calculate(max, '0', PayrollItemRounding.up), 0);
  });

  test('existing fixed and direct amounts stay unchanged and reject count input', () {
    for (final basis in [
      PayrollItemBasis.monthlyFixed, PayrollItemBasis.directAmount,
    ]) {
      final fixed = PayrollItemCondition(
          basis: basis, amountYen: 321, rounding: PayrollItemRounding.down);
      expect(fixed.calculate().amountYen, 321);
      expect(() => fixed.calculate(quantity: PayrollItemQuantity.parse('2')),
          throwsArgumentError);
    }
    expect(PayrollItemCondition.legacyDirect(
        amountYen: 456, rounding: PayrollItemRounding.up)
        .calculate().amountYen, 456);
    expect(PayrollItemBasis.values, hasLength(4));
  });
}

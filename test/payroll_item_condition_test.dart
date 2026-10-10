import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/domain/payroll_item_condition.dart';

void main() {
  PayrollItemCondition item(PayrollItemBasis basis, int yen, PayrollItemRounding rounding) =>
      PayrollItemCondition(basis: basis, amountYen: yen, rounding: rounding);

  test('quantity bases are independent and use exact decimal multiplication', () {
    for (final basis in [PayrollItemBasis.hours, PayrollItemBasis.attendanceDays]) {
      expect(item(basis, 1234, PayrollItemRounding.nearestHalfUp)
          .calculate(quantity: PayrollItemQuantity.parse('1.25')).amountYen, 1543);
      expect(item(basis, 1, PayrollItemRounding.down)
          .calculate(quantity: PayrollItemQuantity.parse('0.9999')).amountYen, 0);
    }
  });
  test('caller controls rounding at the half and sub-half boundary', () {
    for (final entry in {
      PayrollItemRounding.down: 1,
      PayrollItemRounding.up: 2,
      PayrollItemRounding.nearestHalfUp: 2,
    }.entries) {
      expect(item(PayrollItemBasis.hours, 3, entry.key)
          .calculate(quantity: PayrollItemQuantity.parse('0.5')).amountYen, entry.value);
    }
    expect(item(PayrollItemBasis.hours, 1, PayrollItemRounding.nearestHalfUp)
        .calculate(quantity: PayrollItemQuantity.parse('0.4999')).amountYen, 0);
  });
  test('fixed/direct preserve legacy money and reject irrelevant quantity', () {
    for (final basis in [PayrollItemBasis.monthlyFixed, PayrollItemBasis.directAmount]) {
      final condition = item(basis, 4000, PayrollItemRounding.down);
      expect(condition.calculate().amountYen, 4000);
      expect(() => condition.calculate(quantity: PayrollItemQuantity.parse('2')), throwsArgumentError);
    }
    expect(PayrollItemCondition.legacyDirect(amountYen: 321, rounding: PayrollItemRounding.up)
        .calculate().amountYen, 321);
  });
  test('malformed and out of range inputs fail without silent coercion', () {
    for (final input in ['-1', 'NaN', 'Infinity', '1e3', '1.00001', '.5', '1.', ' 1', '']) {
      expect(() => PayrollItemQuantity.parse(input), throwsFormatException);
    }
    expect(() => item(PayrollItemBasis.hours, -1, PayrollItemRounding.down), throwsRangeError);
    expect(() => item(PayrollItemBasis.hours, PayrollItemCondition.maxExactInteger + 1,
        PayrollItemRounding.down), throwsRangeError);
    expect(() => PayrollItemQuantity.parse('9007199254740992'), throwsRangeError);
    expect(() => item(PayrollItemBasis.hours, 1, PayrollItemRounding.down).calculate(), throwsArgumentError);
    expect(() => item(PayrollItemBasis.hours, PayrollItemCondition.maxExactInteger,
        PayrollItemRounding.down).calculate(quantity: PayrollItemQuantity.parse('2')), throwsRangeError);
  });
  test('zero result is suppressed and positive yen remains visible', () {
    expect(item(PayrollItemBasis.hours, 100, PayrollItemRounding.up)
        .calculate(quantity: PayrollItemQuantity.parse('0')).shouldDisplayOnStatement, isFalse);
    expect(item(PayrollItemBasis.directAmount, 0, PayrollItemRounding.up)
        .calculate().shouldDisplayOnStatement, isFalse);
    expect(item(PayrollItemBasis.directAmount, 1, PayrollItemRounding.down)
        .calculate().shouldDisplayOnStatement, isTrue);
  });
  test('family override zero survives new automatic count and resets explicitly', () {
    final automatic = PayrollFamilyCount(automaticCount: 2);
    expect(automatic.effectiveCount, 2);
    final overridden = automatic.overrideWith(0).withAutomaticCount(3);
    expect(overridden.effectiveCount, 0);
    expect(overridden.isAutomatic, isFalse);
    expect(overridden.returnToAutomatic().effectiveCount, 3);
    expect(overridden.returnToAutomatic().isAutomatic, isTrue);
    expect(automatic.effectiveCount, 2);
    expect(() => automatic.overrideWith(-1), throwsRangeError);
    expect(() => automatic.withAutomaticCount(-1), throwsRangeError);
  });
}

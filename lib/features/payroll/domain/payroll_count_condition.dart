import 'payroll_item_condition.dart';

/// Per-item occurrence count, independent of hours, attendance days and pay type.
/// Uses the shared exact decimal parser; does not aggregate reports or resolve prices.
class PayrollCountCondition {
  PayrollCountCondition({
    required this.unitAmountYen,
    required this.rounding,
  }) {
    if (unitAmountYen < 0 ||
        unitAmountYen > PayrollItemCondition.maxExactInteger) {
      throw RangeError.range(unitAmountYen, 0,
          PayrollItemCondition.maxExactInteger, 'unitAmountYen');
    }
  }

  final int unitAmountYen;
  final PayrollItemRounding rounding;

  PayrollCountResult calculate({required PayrollItemQuantity count}) {
    final scale = BigInt.from(PayrollItemQuantity.scale);
    final numerator = BigInt.from(unitAmountYen) * count.scaledValue;
    var yen = numerator ~/ scale;
    final remainder = numerator.remainder(scale);
    if ((rounding == PayrollItemRounding.up && remainder > BigInt.zero) ||
        (rounding == PayrollItemRounding.nearestHalfUp &&
            remainder * BigInt.two >= scale)) {
      yen += BigInt.one;
    }
    if (yen > BigInt.from(PayrollItemCondition.maxExactInteger)) {
      throw RangeError('Calculated count amount exceeds exact integer range');
    }
    return PayrollCountResult._(yen.toInt());
  }
}

/// Result of one explicit count condition, never a stored price or report total.
class PayrollCountResult {
  const PayrollCountResult._(this.amountYen);
  final int amountYen;
  bool get shouldDisplayOnStatement => amountYen != 0;
}

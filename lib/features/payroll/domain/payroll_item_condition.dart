/// Conditions for earnings and company-specific deductions only.
/// Tax and social-insurance calculations use separate contracts.
enum PayrollItemBasis { hours, attendanceDays, monthlyFixed, directAmount }

/// A caller must choose a policy; this model defines no statutory default.
enum PayrollItemRounding { down, up, nearestHalfUp }

/// Decimal quantity with four places, represented without binary floating point.
class PayrollItemQuantity {
  PayrollItemQuantity._(this.scaledValue);
  static const scale = 10000;
  final BigInt scaledValue;

  factory PayrollItemQuantity.parse(String value) {
    if (!RegExp(r'^\d+(?:\.\d{1,4})?$').hasMatch(value)) {
      throw FormatException('Quantity must be a nonnegative decimal with up to four places', value);
    }
    final parts = value.split('.');
    final fraction = parts.length == 2 ? parts[1].padRight(4, '0') : '0000';
    final scaled = BigInt.parse(parts[0]) * BigInt.from(scale) + BigInt.parse(fraction);
    if (scaled > BigInt.from(PayrollItemCondition.maxExactInteger)) {
      throw RangeError('Quantity exceeds the supported exact integer range');
    }
    return PayrollItemQuantity._(scaled);
  }
}

class PayrollItemCondition {
  PayrollItemCondition({
    required this.basis,
    required this.amountYen,
    required this.rounding,
  }) {
    if (amountYen < 0 || amountYen > maxExactInteger) {
      throw RangeError.range(amountYen, 0, maxExactInteger, 'amountYen');
    }
  }

  /// Exact in Dart VM and JavaScript, including serialized integer amounts.
  static const maxExactInteger = 9007199254740991;
  final PayrollItemBasis basis;
  /// Unit price for quantity bases, registered amount for fixed/direct bases.
  final int amountYen;
  final PayrollItemRounding rounding;

  /// Existing name/amount_yen items can enter explicitly as direct amounts.
  factory PayrollItemCondition.legacyDirect({
    required int amountYen,
    required PayrollItemRounding rounding,
  }) => PayrollItemCondition(
    basis: PayrollItemBasis.directAmount,
    amountYen: amountYen,
    rounding: rounding,
  );

  /// Pay type is deliberately absent: every employee may use every basis.
  PayrollItemResult calculate({PayrollItemQuantity? quantity}) {
    final usesQuantity = basis == PayrollItemBasis.hours || basis == PayrollItemBasis.attendanceDays;
    if (usesQuantity != (quantity != null)) {
      throw ArgumentError(usesQuantity
          ? 'Quantity is required for this basis'
          : 'Quantity is not accepted for fixed/direct amounts');
    }
    final scale = BigInt.from(PayrollItemQuantity.scale);
    final numerator = BigInt.from(amountYen) * (quantity?.scaledValue ?? scale);
    var yen = numerator ~/ scale;
    final remainder = numerator.remainder(scale);
    if ((rounding == PayrollItemRounding.up && remainder > BigInt.zero) ||
        (rounding == PayrollItemRounding.nearestHalfUp && remainder * BigInt.two >= scale)) {
      yen += BigInt.one;
    }
    if (yen > BigInt.from(maxExactInteger)) {
      throw RangeError('Calculated yen exceeds the supported exact integer range');
    }
    return PayrollItemResult._(amountYen: yen.toInt());
  }
}

class PayrollItemResult {
  const PayrollItemResult._({required this.amountYen});
  final int amountYen;
  bool get shouldDisplayOnStatement => amountYen != 0;
}

/// Receives an already validated eligible count from the future family adapter.
/// It does not decide eligibility, access family records, or calculate tax dependants.
class PayrollFamilyCount {
  PayrollFamilyCount({required this.automaticCount, this.manualCount}) {
    _validate(automaticCount);
    if (manualCount != null) _validate(manualCount!);
  }
  final int automaticCount;
  final int? manualCount;
  int get effectiveCount => manualCount ?? automaticCount;
  bool get isAutomatic => manualCount == null;
  PayrollFamilyCount overrideWith(int count) => PayrollFamilyCount(automaticCount: automaticCount, manualCount: count);
  PayrollFamilyCount returnToAutomatic() => PayrollFamilyCount(automaticCount: automaticCount);
  PayrollFamilyCount withAutomaticCount(int count) => PayrollFamilyCount(automaticCount: count, manualCount: manualCount);
  static void _validate(int count) {
    if (count < 0 || count > PayrollItemCondition.maxExactInteger) {
      throw RangeError.range(count, 0, PayrollItemCondition.maxExactInteger, 'count');
    }
  }
}

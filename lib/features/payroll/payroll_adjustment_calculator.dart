import 'payroll_adjustment_model.dart';

class PayrollAdjustmentSummary {
  const PayrollAdjustmentSummary({
    required this.additionsYen,
    required this.deductionsYen,
    required this.netAdjustmentYen,
  });

  final int additionsYen;
  final int deductionsYen;
  final int netAdjustmentYen;
}

class PayrollAdjustmentCalculator {
  const PayrollAdjustmentCalculator._();

  static PayrollAdjustmentSummary summarize(
    Iterable<PayrollAdjustmentRecord> records,
  ) {
    var additions = 0;
    var deductions = 0;

    for (final record in records) {
      if (record.isCancelled) continue;
      switch (record.direction) {
        case PayrollAdjustmentDirection.addition:
          additions += record.amountYen;
        case PayrollAdjustmentDirection.deduction:
          deductions += record.amountYen;
      }
    }

    return PayrollAdjustmentSummary(
      additionsYen: additions,
      deductionsYen: deductions,
      netAdjustmentYen: additions - deductions,
    );
  }

  static Map<String, int> detailByLabel(
    Iterable<PayrollAdjustmentRecord> records,
  ) {
    final result = <String, int>{};
    for (final record in records) {
      final signed = record.signedAmountYen;
      if (signed == 0) continue;
      result.update(
        record.labelSnapshot,
        (value) => value + signed,
        ifAbsent: () => signed,
      );
    }
    return result;
  }
}

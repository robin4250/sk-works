import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/payroll_adjustment_calculator.dart';
import 'package:sk_works/features/payroll/payroll_adjustment_model.dart';

PayrollAdjustmentRecord record({
  required String id,
  required String label,
  required PayrollAdjustmentDirection direction,
  required int amount,
  DateTime? cancelledAt,
}) {
  return PayrollAdjustmentRecord(
    id: id,
    companyId: 'company-1',
    workerId: 'worker-1',
    typeId: 'type-1',
    labelSnapshot: label,
    direction: direction,
    amountYen: amount,
    effectiveDate: DateTime(2026, 9, 29),
    createdByUserId: 'user-1',
    createdAt: DateTime(2026, 9, 29),
    cancelledAt: cancelledAt,
  );
}

void main() {
  test('salary adjustment summary separates additions and deductions', () {
    final summary = PayrollAdjustmentCalculator.summarize([
      record(
        id: '1',
        label: '前借り',
        direction: PayrollAdjustmentDirection.deduction,
        amount: 10000,
      ),
      record(
        id: '2',
        label: '交通費',
        direction: PayrollAdjustmentDirection.addition,
        amount: 3000,
      ),
    ]);

    expect(summary.additionsYen, 3000);
    expect(summary.deductionsYen, 10000);
    expect(summary.netAdjustmentYen, -7000);
  });

  test('cancelled adjustments do not affect payroll totals', () {
    final summary = PayrollAdjustmentCalculator.summarize([
      record(
        id: '1',
        label: '前借り',
        direction: PayrollAdjustmentDirection.deduction,
        amount: 10000,
        cancelledAt: DateTime(2026, 9, 30),
      ),
    ]);

    expect(summary.netAdjustmentYen, 0);
  });

  test('detail groups company-defined labels while keeping their sign', () {
    final detail = PayrollAdjustmentCalculator.detailByLabel([
      record(
        id: '1',
        label: '道具代',
        direction: PayrollAdjustmentDirection.deduction,
        amount: 2500,
      ),
      record(
        id: '2',
        label: '道具代',
        direction: PayrollAdjustmentDirection.deduction,
        amount: 1500,
      ),
      record(
        id: '3',
        label: '立替精算',
        direction: PayrollAdjustmentDirection.addition,
        amount: 800,
      ),
    ]);

    expect(detail['道具代'], -4000);
    expect(detail['立替精算'], 800);
  });
}

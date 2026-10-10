import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/settings/payroll_rate_month_picker.dart';

void main() {
  test('December payroll defaults to next January payment', () {
    expect(payrollRateStartingMonths(DateTime(2026, 12, 31)), {
      'insurance_month': '2026-12',
      'payroll_month': '2026-12',
      'payment_month': '2027-01',
    });
  });

  testWidgets('month can be changed without typing; cancellation keeps value', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var value = '2026-12';
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                value =
                    await showPayrollRateMonthPicker(context, value) ?? value;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('翌年'));
    await tester.pumpAndSettle();
    expect(find.text('2027年'), findsOneWidget);
    await tester.tap(find.text('1月'));
    await tester.pumpAndSettle();
    expect(value, '2027-01');
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('前年'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(value, '2027-01');
    expect(tester.takeException(), isNull);
  });
}

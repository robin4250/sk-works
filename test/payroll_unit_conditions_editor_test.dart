import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/payroll_unit_item_editor.dart';
import 'package:sk_works/features/payroll/payroll_unit_conditions_repository.dart';

void main() {
  test('saved unit data restores each basis and explicit monthly hours', () {
    final value = PayrollUnitConditions.fromJson({
      'version': 2,
      'month': '2026-10-01',
      'can_edit': true,
      'items': [
        for (final section in ['earning', 'deduction'])
          for (final unit in ['hour', 'day', 'month'])
            {
              'id': '$section-$unit',
              'section': section,
              'unit': unit,
              'name': '$section $unit',
              'rate_yen': 500,
              'source': unit == 'hour'
                  ? 'manual_hours'
                  : unit == 'day'
                  ? 'attendance_days'
                  : 'monthly_fixed',
              'quantity': unit == 'hour' ? 2.5 : null,
            },
      ],
    });
    expect(value.items.length, 6);
    expect(value.items.first.quantity, '2.5');
    expect(value.items.last.section, PayrollItemSection.deduction);
    expect(value.items.last.unit, PayrollItemUnit.month);
    expect(value.items.last.quantity, '');
    expect(
      () => PayrollUnitConditions.fromJson({
        'version': 1,
        'month': '2026-10-01',
        'items': [
          {'id': 'bad'},
        ],
      }),
      throwsStateError,
    );
  });
  testWidgets(
    'real quantity editor requires explicit hours and retains values across units',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      List<PayrollUnitItemDraft>? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PayrollUnitItemEditor(
              canEdit: true,
              enableQuantitySources: true,
              showDailyReportOption: false,
              initialItems: const [
                PayrollUnitItemDraft(
                  id: 'hours',
                  section: PayrollItemSection.earning,
                  unit: PayrollItemUnit.hour,
                  name: '時間手当',
                  rate: '100',
                ),
              ],
              onRegister: (items) async => saved = items,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Checkbox), findsNothing);
      await tester.tap(find.text('登録'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      expect(find.text('対象月の時間数を入力してください'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('hours-quantity')),
        '2.5',
      );
      await tester.tap(find.text('月単位'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('時間単位'));
      await tester.pumpAndSettle();
      expect(find.text('2.5'), findsOneWidget);
      await tester.tap(find.text('登録'));
      await tester.pumpAndSettle();
      expect(saved!.single.source, 'manual_hours');
      expect(saved!.single.quantity, '2.5');
      expect(tester.takeException(), isNull);
    },
  );
}

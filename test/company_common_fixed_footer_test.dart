import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/company_common_payroll_page.dart';
import 'package:sk_works/features/payroll/payroll_unit_item_editor.dart';

void main() {
  final footer = find.byKey(const ValueKey('company-common-fixed-footer'));
  for (final type in CompanyPayrollType.values) {
    testWidgets('${type.name} common actions stay fixed and delegate each section/unit', (tester) async {
      final savedTypes = <CompanyPayrollType>[];
      final savedRows = <List<PayrollUnitItemDraft>>[];
      await tester.pumpWidget(MaterialApp(home: CompanyCommonPayrollPage(
        canEdit: true,
        onRegister: (value, items) async { savedTypes.add(value); savedRows.add(items); },
      )));
      await tester.pumpAndSettle();
      final typeLabel = switch (type) { CompanyPayrollType.daily => '日給', CompanyPayrollType.hourly => '時給', CompanyPayrollType.monthly => '月給' };
      await tester.tap(find.widgetWithText(OutlinedButton, typeLabel));
      await tester.pumpAndSettle();
      var rowIndex = 0;
      for (final section in PayrollItemSection.values) {
        await tester.ensureVisible(find.widgetWithText(OutlinedButton, section == PayrollItemSection.earning ? '支給' : '控除'));
        await tester.tap(find.widgetWithText(OutlinedButton, section == PayrollItemSection.earning ? '支給' : '控除'));
        await tester.pumpAndSettle();
        for (final unit in PayrollItemUnit.values) {
          final unitLabel = switch (unit) { PayrollItemUnit.hour => '時間単位', PayrollItemUnit.day => '日単位', PayrollItemUnit.month => '月単位' };
          await tester.ensureVisible(find.widgetWithText(OutlinedButton, unitLabel));
          await tester.tap(find.widgetWithText(OutlinedButton, unitLabel));
          await tester.pumpAndSettle();
          expect(find.text('追加'), findsOneWidget);
          expect(find.text('登録'), findsOneWidget);
          final bounds = tester.getRect(footer);
          await tester.tap(find.descendant(of: footer, matching: find.text('追加')));
          await tester.pumpAndSettle();
          final name = find.byKey(ValueKey('new-unit-item-$rowIndex-name'));
          final rate = find.byKey(ValueKey('new-unit-item-$rowIndex-rate'));
          await tester.ensureVisible(name);
          await tester.enterText(name, '追加-${section.name}-${unit.name}');
          await tester.ensureVisible(rate); await tester.enterText(rate, '321');
          FocusManager.instance.primaryFocus?.unfocus(); await tester.pumpAndSettle();
          await tester.drag(find.byType(Scrollable).first, const Offset(0, -120));
          await tester.pumpAndSettle();
          expect(tester.getRect(footer), bounds);
          await tester.tap(find.descendant(of: footer, matching: find.text('登録')));
          await tester.pumpAndSettle();
          expect(savedTypes.last, type);
          expect(savedRows.last.last.section, section);
          expect(savedRows.last.last.unit, unit);
          expect(savedRows.last.last.rate, '321');
          rowIndex++;
        }
      }
      expect(savedTypes.length, 6);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('embedded disconnected common footer remains disabled', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body:
        CompanyCommonPayrollPage(embedded: true))));
    await tester.pumpAndSettle();
    expect(footer, findsOneWidget);
    expect(find.textContaining('接続準備中'), findsOneWidget);
    final add = find.descendant(of: footer, matching: find.byType(OutlinedButton));
    final register = find.descendant(of: footer, matching: find.byType(FilledButton));
    expect(tester.widget<OutlinedButton>(add).onPressed, isNull);
    expect(tester.widget<FilledButton>(register).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
}

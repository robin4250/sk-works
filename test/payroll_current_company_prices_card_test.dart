import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/payroll_company_common_card.dart';
import 'package:sk_works/features/payroll/payroll_unit_item_editor.dart';

void main() {
  for (final unit in PayrollItemUnit.values) {
    testWidgets('current price is read only for ${unit.name}', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body:
        PayrollCompanyRegisteredNamesCard(unit: unit, items: [
          PayrollRegisteredAllowanceName(key: 'current', name: '現在手当',
            section: PayrollItemSection.earning, unit: unit,
            displayUnit: '対象単位', currentRateYen: 2300),
          PayrollRegisteredAllowanceName(key: 'unknown', name: '未確認手当',
            section: PayrollItemSection.earning, unit: unit),
        ]))));
      expect(find.text('2300円／対象単位'), findsOneWidget);
      expect(find.text('単価未確認'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });
  }
}

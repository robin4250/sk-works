import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/resident_tax_annual_entry_card.dart';

void main() {
  testWidgets('annual entry opens once from the payroll rates card', (tester) async {
    var opened = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      ResidentTaxAnnualEntryCard(onOpen: () => opened++))));
    expect(find.text('住民税一括入力'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('resident-tax-annual-entry')));
    await tester.pump();
    expect(opened, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('busy annual entry cannot open another editor', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body:
      ResidentTaxAnnualEntryCard(onOpen: null))));
    final tile = tester.widget<ListTile>(find.byKey(const ValueKey('resident-tax-annual-entry')));
    expect(tile.onTap, isNull);
    expect(find.text('住民税一括入力'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/companies/company_invite_recipient_picker.dart';
import 'package:sk_works/features/companies/trade_company_repository.dart';

void main() {
  testWidgets('company choice retains representative contact and manual choice is independent',
      (tester) async {
    final company = TradeCompanyRecord.fromJson({
      'id': 'local-company', 'name': '協力会社A', 'trade_role': 'subcontractor',
      'phone': '0312345678', 'representative_name': '代表者A',
      'representative_phone': '09012345678',
    });
    final choices = <TradeCompanyRecord?>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: CompanyInviteRecipientPicker(companies: [company], onSelected: choices.add),
    )));
    expect(find.textContaining('09012345678'), findsOneWidget);
    expect(find.textContaining('0312345678'), findsNothing);
    await tester.tap(find.text('協力会社A'));
    expect(choices.single, same(company));
    await tester.tap(find.text('電話番号を直接入力'));
    expect(choices, [company, null]);
  });

  testWidgets('empty directory still permits manual entry and missing representative is explicit',
      (tester) async {
    TradeCompanyRecord? selected;
    var calls = 0;
    Future<void> show(List<TradeCompanyRecord> companies) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: CompanyInviteRecipientPicker(
          companies: companies,
          onSelected: (value) { selected = value; calls++; },
        ),
      )));
    }
    await show([]);
    await tester.tap(find.text('電話番号を直接入力'));
    expect(calls, 1);
    expect(selected, isNull);
    await show([TradeCompanyRecord.fromJson({
      'id': 'existing', 'name': '取引会社B', 'phone': '0311111111',
    })]);
    expect(find.textContaining('次の画面で入力'), findsOneWidget);
    expect(find.textContaining('0311111111'), findsNothing);
    await tester.tap(find.text('取引会社B'));
    expect(selected?.id, 'existing');
    expect(selected?.representativePhone, isEmpty);
  });
}

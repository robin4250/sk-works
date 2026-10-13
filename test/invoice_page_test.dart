import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/invoices/invoice_page.dart';

void main() {
  testWidgets('invoice page shows consolidated sample invoice', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: InvoicePage()));

    expect(find.text('株式会社ABC'), findsOneWidget);
    expect(find.text('2026年9月'), findsOneWidget);
    expect(find.text('請求作成'), findsOneWidget);
    expect(find.textContaining('2現場'), findsOneWidget);
  });

  testWidgets('invoice sample opens site detail breakdown', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: InvoicePage()));

    await tester.tap(find.text('株式会社ABC'));
    await tester.pumpAndSettle();

    expect(find.text('墨田区〇〇改修工事'), findsOneWidget);
    expect(find.text('江東区△△新築工事'), findsOneWidget);
    expect(find.text('請求合計'), findsOneWidget);
  });
}

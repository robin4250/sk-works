import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/invoices/invoice_empty_state.dart';

void main() {
  testWidgets('empty list exposes reload without generating invoice data', (tester) async {
    var reloads = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: InvoiceEmptyState(
      onReload: () async { reloads++; },
      showGenerationGuidance: true,
    ))));
    expect(find.text('この期間の請求書はありません'), findsOneWidget);
    expect(find.textContaining('数量・単価の承認'), findsOneWidget);
    await tester.tap(find.text('一覧を再読み込み'));
    expect(reloads, 1);
  });
  testWidgets('view-only empty list omits management steps and remains scrollable', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(
      height: 120,
      child: InvoiceEmptyState(onReload: () async {}, showGenerationGuidance: false),
    ))));
    expect(find.textContaining('数量・単価の承認'), findsNothing);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

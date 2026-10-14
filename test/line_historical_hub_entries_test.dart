import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/chat/line_talk_hub_page.dart';
import 'package:sk_works/features/chat/line_historical_invoice_page.dart';
import 'package:sk_works/features/chat/line_import_page.dart';
import 'package:sk_works/features/chat/line_import_repository.dart';

void main() {
  testWidgets('master historical invoices and rates remain available when optional feature settings fail', (tester) async {
    await tester.pumpWidget(MaterialApp(home: LineTalkHubPage(
      accessLoader: () async => const LineTalkHubAccess(
        isMaster: true, settingsUnavailable: true))));
    await tester.pumpAndSettle();
    expect(find.text('請求書'), findsOneWidget);
    expect(find.text('単価設定'), findsOneWidget);
    expect(find.text('出勤表'), findsNothing);
    await tester.tap(find.text('請求書'));
    await tester.pumpAndSettle();
    expect(tester.widget<LineHistoricalInvoicePage>(
      find.byType(LineHistoricalInvoicePage)).editingRates, false);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('単価設定'));
    await tester.pumpAndSettle();
    expect(tester.widget<LineHistoricalInvoicePage>(
      find.byType(LineHistoricalInvoicePage)).editingRates, true);
  });
  testWidgets('non-master cannot expose historical rates through ordinary invoice feature', (tester) async {
    await tester.pumpWidget(MaterialApp(home: LineTalkHubPage(
      accessLoader: () async => const LineTalkHubAccess(
        canViewInvoice: true, features: LineImportFeatures(invoice: true)))));
    await tester.pumpAndSettle();
    expect(find.text('単価設定'), findsNothing);
    expect(find.text('マスター権限'), findsNothing);
    await tester.tap(find.text('請求書'));
    await tester.pumpAndSettle();
    expect(find.byType(LineImportPage), findsOneWidget);
    expect(find.byType(LineHistoricalInvoicePage), findsNothing);
  });
  testWidgets('unavailable or denied invoice access cannot expose ordinary invoice entry', (tester) async {
    await tester.pumpWidget(MaterialApp(home: LineTalkHubPage(
      accessLoader: () async => const LineTalkHubAccess(
        features: LineImportFeatures(invoice: true)))));
    await tester.pumpAndSettle();
    expect(find.text('請求書'), findsNothing);
    expect(find.text('単価設定'), findsNothing);
  });
}

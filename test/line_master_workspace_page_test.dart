import 'support/line_test_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/chat/line_master_workspace_page.dart';
import 'package:sk_works/international/language_controller.dart';
import 'package:sk_works/international/languages/en/english_language_pack.dart';
import 'package:sk_works/features/chat/line_historical_invoice_page.dart';

void main() {
  testWidgets('master workspace has four billing entries plus chat and keeps 320px layout readable',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(LineTestApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
        child: child!,
      ),
      home: LineMasterWorkspacePage(masterCheck: () async => true),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('line-master-chat')), findsOneWidget);
    expect(find.byKey(const ValueKey('line-master-invoices')), findsOneWidget);
    expect(find.byKey(const ValueKey('line-master-rates')), findsOneWidget);
    expect(find.byKey(const ValueKey('line-master-monthly')), findsOneWidget);
    expect(find.byKey(const ValueKey('line-master-upload')), findsOneWidget);
    expect(find.text('すみだ建設出勤'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('master entries use the shared English language pack', (tester) async {
    final previous = SkoLanguageController.pack.value;
    SkoLanguageController.pack.value = englishLanguagePack;
    addTearDown(() => SkoLanguageController.pack.value = previous);
    await tester.pumpWidget(LineTestApp(
      home: LineMasterWorkspacePage(masterCheck: () async => true),
    ));
    await tester.pumpAndSettle();
    expect(find.text('LINE Master Access'), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Invoices'), findsOneWidget);
    expect(find.text('Unit Rates'), findsOneWidget);
    expect(find.text('Monthly Table'), findsOneWidget);
  });

  testWidgets('non-master cannot see or open master entries', (tester) async {
    await tester.pumpWidget(LineTestApp(
      home: LineMasterWorkspacePage(masterCheck: () async => false),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsNothing);
    expect(find.text('マスター権限でログインしてください。'), findsOneWidget);
  });

  testWidgets('each entry opens its own page and rechecks master on return',
      (tester) async {
    var checks = 0;
    await tester.pumpWidget(LineTestApp(home: LineMasterWorkspacePage(
      masterCheck: () async { checks++; return true; },
      talkBuilder: (_) => const Scaffold(body: Text('received-source-page')),
      invoiceBuilder: (_) => const Scaffold(body: Text('monthly-invoice-page')),
      ratesBuilder: (_) => const Scaffold(body: Text('historical-rates-page')),
      monthlyBuilder: (_) => const Scaffold(body: Text('editable-monthly-page')),
    )));
    await tester.pumpAndSettle();
    for (final entry in const {
      'line-master-chat': 'received-source-page',
      'line-master-invoices': 'monthly-invoice-page',
      'line-master-rates': 'historical-rates-page',
      'line-master-monthly': 'editable-monthly-page',
    }.entries) {
      await tester.ensureVisible(find.byKey(ValueKey(entry.key)));
      await tester.tap(find.byKey(ValueKey(entry.key)));
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
    }
    expect(checks, 9);
  });

  testWidgets('master revoked before navigation never builds protected page',
      (tester) async {
    var master = true, opened = false;
    await tester.pumpWidget(LineTestApp(home: LineMasterWorkspacePage(
      masterCheck: () async => master,
      ratesBuilder: (_) { opened = true; return const Scaffold(); },
    )));
    await tester.pumpAndSettle();
    master = false;
    await tester.tap(find.byKey(const ValueKey('line-master-rates')));
    await tester.pumpAndSettle();
    expect(opened, false);
    expect(find.byType(ListTile), findsNothing);
  });

  test('historical invoices and rates use distinct modes with same month/source', () {
    final month = DateTime(2025, 9);
    final invoice = LineHistoricalInvoicePage(initialGroupId: 'actual-group', initialMonth: month);
    final rates = LineHistoricalInvoicePage.rates(initialGroupId: invoice.initialGroupId, initialMonth: invoice.initialMonth);
    expect(invoice.editingRates, false);
    expect(rates.editingRates, true);
    expect(rates.initialGroupId, 'actual-group');
    expect(rates.initialMonth, month);
  });
}



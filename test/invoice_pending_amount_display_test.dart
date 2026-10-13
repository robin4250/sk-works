import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/domain/invoice_engine.dart';
import 'package:sk_works/features/invoices/invoice_list_card.dart';

InvoiceCalculationResult _invoice({required bool pending, int amount = 0, bool sourcePending = false}) =>
    InvoiceEngine.calculate(
      customerId: '株式会社秀中',
      billingPeriod: '2026年10月',
      detailMode: InvoiceDetailMode.consolidatedOnly,
      sites: const [],
      grandTotalYenOverride: amount,
      routeQuantityPending: pending,
      routeSourcePending: sourcePending,
    );

void main() {
  testWidgets('pending saved zero is shown as unconfirmed with usable card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var tapped = 0;
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: Scaffold(body: InvoiceListCard(
          invoice: _invoice(pending: true),
          periodLabel: '2026年10月',
          onTap: () => tapped++,
        )),
      ),
    ));
    expect(find.text('未確定'), findsOneWidget);
    expect(find.text('請求数量の承認待ち'), findsOneWidget);
    expect(find.text('¥0'), findsNothing);
    expect(find.text('0現場'), findsNothing);
    await tester.tap(find.text('未確定'));
    expect(tapped, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('actual ready zero remains zero and pending partial totals are hidden', (
    tester,
  ) async {
    for (final value in [(false, 0), (false, 44000), (true, 44000)]) {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: InvoiceListCard(
        invoice: _invoice(pending: value.$1, amount: value.$2),
        periodLabel: '2026年10月',
        onTap: () {},
      ))));
      expect(find.text('未確定'), value.$1 ? findsOneWidget : findsNothing);
      expect(find.text(invoiceAmountLabel(value.$2)),
          value.$1 ? findsNothing : findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('unready signed source hides zero without requiring quantity approval', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: InvoiceListCard(
      invoice: _invoice(pending: false, sourcePending: true),
      periodLabel: '2026年10月', onTap: () {},
    ))));
    expect(find.text('未確定'), findsOneWidget);
    expect(find.text('退勤日報・請求設定の確認待ち'), findsOneWidget);
    expect(find.text('請求数量の承認待ち'), findsNothing);
    expect(find.text('¥0'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

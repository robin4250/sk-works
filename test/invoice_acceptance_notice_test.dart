import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/invoices/invoice_acceptance_notice.dart';
import 'package:sk_works/international/language_controller.dart';
import 'package:sk_works/international/language_pack_registry.dart';

void main() {
  setUp(() {
    final previous = SkoLanguageController.pack.value;
    SkoLanguageController.pack.value = LanguagePackRegistry.resolve('ja');
    addTearDown(() => SkoLanguageController.pack.value = previous);
  });

  testWidgets('missing single acceptance offers review without acting until tapped',
      (tester) async {
    var opens = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: InvoiceAcceptanceNotice(
        missingCount: 1, singleInvoice: true, onReview: () { opens++; },
      ),
    )));
    expect(find.text('注文請書が未添付です。'), findsOneWidget);
    expect(find.textContaining('自動追加していません'), findsOneWidget);
    expect(opens, 0);
    await tester.tap(find.text('注文請書を確認・添付'));
    expect(opens, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no missing appendix offers no review action', (tester) async {
    var opens = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: InvoiceAcceptanceNotice(
        missingCount: 0, singleInvoice: true, onReview: () { opens++; },
      ),
    )));
    expect(find.byWidgetPredicate((widget) => widget is OutlinedButton), findsNothing);
    expect(find.textContaining('未添付'), findsNothing);
    expect(opens, 0);
  });

  testWidgets('multiple invoices require opening each and never expose bulk attachment',
      (tester) async {
    var opens = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: InvoiceAcceptanceNotice(
        missingCount: 2, singleInvoice: false, onReview: () { opens++; },
      ),
    )));
    expect(find.text('請求書2件に注文請書が未添付です。'), findsOneWidget);
    expect(find.textContaining('各請求書を個別に'), findsOneWidget);
    expect(find.byWidgetPredicate((widget) => widget is OutlinedButton), findsNothing);
    expect(opens, 0);
  });

  testWidgets('pending or unavailable editor disables the review action',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(
      body: InvoiceAcceptanceNotice(missingCount: 1, singleInvoice: true),
    )));
    expect(tester.widget<OutlinedButton>(find.byWidgetPredicate((widget) => widget is OutlinedButton)).onPressed,
        isNull);
  });

  testWidgets('English guidance and review remain usable on a narrow screen',
      (tester) async {
    SkoLanguageController.pack.value = LanguagePackRegistry.resolve('en');
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var opens = 0;
    await tester.pumpWidget(MaterialApp(home: MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
      child: Scaffold(body: InvoiceAcceptanceNotice(
        missingCount: 1, singleInvoice: true, onReview: () { opens++; },
      )),
    )));
    expect(find.text('The order acceptance is not attached.'), findsOneWidget);
    expect(find.textContaining('preserving the original invoice'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byWidgetPredicate((widget) => widget is OutlinedButton));
    expect(opens, 1);
    expect(tester.takeException(), isNull);
  });
}


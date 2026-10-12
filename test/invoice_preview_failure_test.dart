import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/invoices/invoice_preview_failure.dart';
import 'package:sk_works/international/language_controller.dart';
import 'package:sk_works/international/language_pack_registry.dart';

void main() {
  testWidgets('short screen and enlarged text expose retry without overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 180);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var retries = 0;
    await tester.pumpWidget(MaterialApp(home: MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
      child: Scaffold(body: InvoicePreviewFailure(
        title: 'PDFを表示できませんでした',
        message: 'PDFの画面表示に時間がかかっています。再試行してください。',
        onRetry: () { retries++; },
        pdfReady: true,
      )),
    )));
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.tap(find.byType(FilledButton));
    expect(retries, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('English error instructions use common language pack', (tester) async {
    final previous = SkoLanguageController.pack.value;
    SkoLanguageController.pack.value = LanguagePackRegistry.resolve('en');
    addTearDown(() { SkoLanguageController.pack.value = previous; });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: InvoicePreviewFailure(
      title: 'PDFを表示できませんでした', message: 'Native raster unavailable',
      onRetry: () {}, pdfReady: true,
    ))));
    expect(find.text('The PDF could not be displayed'), findsOneWidget);
    expect(find.textContaining('same PDF'), findsOneWidget);
    expect(find.text('再試行'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

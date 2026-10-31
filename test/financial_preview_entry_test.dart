import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
// The pinned printing 5.15.1 interface lets the actual entry build without a
// platform printer or network raster service.
// ignore: implementation_imports
import 'package:printing/src/interface.dart' show PrintingPlatform;
import 'package:sk_works/domain/invoice_engine.dart';
import 'package:sk_works/features/invoices/invoice_cloud_page.dart';
import 'package:sk_works/features/payroll/payment_certificate_repository.dart';
import 'package:sk_works/features/payroll/payment_certificates_page.dart';
import 'package:sk_works/features/shared/financial_preview_chrome.dart';

class _Printer extends PrintingPlatform {
  @override
  Future<PrintingInfo> info() async =>
      const PrintingInfo(canPrint: true, canShare: true, canRaster: true);
  @override
  Stream<PdfRaster> raster(
    Uint8List document,
    List<int>? pages,
    double dpi,
  ) async* {
    expect(String.fromCharCodes(document.take(4)), '%PDF');
    yield PdfRaster(1, 1, Uint8List.fromList([255, 255, 255, 255]));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PrintingPlatform original;
  setUp(() {
    original = PrintingPlatform.instance;
    PrintingPlatform.instance = _Printer();
  });
  tearDown(() {
    PrintingPlatform.instance = original;
  });
  for (final payment in [false, true]) {
    testWidgets(
      'actual ${payment ? 'payment' : 'invoice'} entry keeps one compact footer',
      (tester) async {
        tester.view.physicalSize = const Size(430, 932);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final invoice = InvoiceEngine.calculate(
          customerId: 'Synthetic company',
          billingPeriod: '2026年9月',
          detailMode: InvoiceDetailMode.siteBreakdownOnInvoice,
          sites: const [
            SiteInvoiceCalculation(
              siteId: 'synthetic-site',
              siteName: 'Synthetic site',
              lines: [
                InvoiceLine(label: 'work', quantity: 1, unitPriceYen: 100),
              ],
            ),
          ],
        );
        final record = PaymentCertificateRecord(
          id: 'synthetic-preview',
          partnerCompanyName: 'Synthetic partner',
          periodStart: DateTime(2026, 9),
          periodEnd: DateTime(2026, 9, 30),
          grossAmount: 100,
          deductions: 0,
          netAmount: 100,
          status: 'preview',
          revision: 1,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: payment
                ? PaymentCertificatePreviewPage(record: record)
                : InvoicePreviewPage(invoice: invoice),
          ),
        );
        // PDF font fallback and PNG conversion use real async work; advance them
        // outside FakeAsync, then render frames. No timeout enlargement or real RPC.
        for (
          var stage = 0;
          stage < 100 && find.byType(FinancialPreviewChrome).evaluate().isEmpty;
          stage++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        expect(find.byType(FinancialPreviewChrome), findsOneWidget);
        expect(find.byType(Scaffold), findsOneWidget);
        final viewport = tester.getSize(
          find.byKey(const ValueKey('financial_preview_document_viewport')),
        );
        expect(viewport.height, greaterThan(550));
        expect(
          find.byKey(const ValueKey('financial_preview_footer')),
          findsOneWidget,
        );
        if (payment) {
          final preview = tester.widget<PdfPreview>(find.byType(PdfPreview));
          expect(preview.useActions, isFalse);
          expect(preview.initialPageFormat, PdfPageFormat.a4);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      },
    );
  }
}

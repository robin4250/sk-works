import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/domain/invoice_engine.dart';
import 'package:sk_works/features/invoices/invoice_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final invoice = InvoiceEngine.calculate(
    customerId: '株式会社テスト',
    billingPeriod: '2026年9月',
    detailMode: InvoiceDetailMode.siteBreakdownOnInvoice,
    sites: const [
      SiteInvoiceCalculation(
        siteId: 'site-1',
        siteName: '新宿現場',
        welfareRateBps: 150,
        lines: [
          InvoiceLine(
            label: '人工',
            quantity: 2,
            unitPriceYen: 25000,
          ),
        ],
      ),
    ],
    taxRateBps: 1000,
  );

  test('invoice PDF snapshot contains Japanese invoice content and totals', () {
    final text = InvoicePdfService.buildTextSnapshot([invoice]);

    expect(text, contains('請求書'));
    expect(text, contains('株式会社テスト'));
    expect(text, contains('新宿現場'));
    expect(text, contains('人工'));
    expect(text, contains('¥50,000'));
    expect(text, contains('請求合計'));
  });

  test('invoice file name is sanitized', () {
    final unsafe = InvoiceEngine.calculate(
      customerId: 'A/B株式会社',
      billingPeriod: '2026年9月',
      detailMode: InvoiceDetailMode.consolidatedOnly,
      sites: const [
        SiteInvoiceCalculation(
          siteId: 'site-2',
          siteName: '現場',
          lines: [
            InvoiceLine(label: '作業', quantity: 1, unitPriceYen: 1000),
          ],
        ),
      ],
    );

    final filename = InvoicePdfService.fileNameFor([unsafe]);

    expect(filename, endsWith('.pdf'));
    expect(filename, isNot(contains('/')));
  });

  test('annual PDF snapshot includes all invoices and title', () {
    final text = InvoicePdfService.buildTextSnapshot(
      [invoice, invoice],
      title: '2026年 請求書',
    );

    expect(text, contains('2026年 請求書'));
    expect(RegExp('株式会社テスト').allMatches(text).length, 2);
  });

  test('dense invoice preview uses adaptive compact layout contract', () {
    final pdf = File(
      'lib/features/invoices/invoice_pdf_service.dart',
    ).readAsStringSync();

    expect(pdf, contains('final detailRowCount = rows.length'));
    expect(pdf, contains('detailRowCount > 12'));
    expect(pdf, contains('detailFontSize'));
    expect(pdf, contains('detailVerticalPadding'));
    expect(pdf, contains('height: 47'));
    expect(pdf, contains('Future<_InvoicePreviewData> _buildPreviewData()'));
    expect(pdf, contains('Printing.raster('));
    expect(pdf, contains('pages.add(await page.toPng())'));
    expect(pdf, contains('請求書プレビューを生成できませんでした'));
    expect(pdf, contains('onLayout: (_) async => pdfBytes'));
    expect(pdf, contains('bytes: pdfBytes'));
  });
}

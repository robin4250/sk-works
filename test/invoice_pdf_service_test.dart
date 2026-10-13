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
        lines: [InvoiceLine(label: '人工', quantity: 2, unitPriceYen: 25000)],
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

  test('invoice text snapshot hides zero quantities and amounts while retaining nonzero values', () {
    final zero = InvoiceEngine.calculate(
      customerId: '会社',
      billingPeriod: '2026年10月',
      detailMode: InvoiceDetailMode.siteBreakdownOnInvoice,
      sites: const [
        SiteInvoiceCalculation(
          siteId: 'zero',
          siteName: '未設定現場',
          lines: [InvoiceLine(label: '未設定作業', quantity: 0, unitPriceYen: 0)],
        ),
      ],
    );
    final zeroText = InvoicePdfService.buildTextSnapshot([zero]);
    expect(zeroText, contains('未設定作業  ×  = '));
    expect(zeroText, isNot(contains('¥0')));
    final nonzero = InvoicePdfService.buildTextSnapshot([invoice]);
    expect(nonzero, contains('人工 2 × ¥25,000 = ¥50,000'));
  });

  test('welfare labels use each saved site rate without adding duplicate snapshot welfare rows', () {
    final rates = InvoiceEngine.calculate(
      customerId: '会社',
      billingPeriod: '2026年10月',
      detailMode: InvoiceDetailMode.siteBreakdownOnInvoice,
      sites: const [
        SiteInvoiceCalculation(
          siteId: 'a',
          siteName: 'A現場',
          welfareRateBps: 300,
          baseAmountYenOverride: 100000,
          welfareAmountYenOverride: 3000,
          subtotalYenOverride: 103000,
          lines: [
            InvoiceLine(label: '通常作業', quantity: 1, unitPriceYen: 100000),
            InvoiceLine(
              label: '（法定福利費）',
              quantity: 0,
              unitPriceYen: 0,
              amountYenOverride: 3000,
            ),
          ],
        ),
        SiteInvoiceCalculation(
          siteId: 'b',
          siteName: 'B現場',
          welfareRateBps: 150,
          baseAmountYenOverride: 100000,
          welfareAmountYenOverride: 1500,
          subtotalYenOverride: 101500,
          lines: [
            InvoiceLine(label: '通常作業', quantity: 1, unitPriceYen: 100000),
          ],
        ),
      ],
    );
    final text = InvoicePdfService.buildTextSnapshot([rates]);
    expect('福利厚生費'.allMatches(text), hasLength(2));
    expect(text, contains('福利厚生費（3%）'));
    expect(text, contains('福利厚生費（1.5%）'));
    expect(text, contains('¥3,000'));
    expect(text, contains('¥1,500'));
    expect(text, contains('計 ¥204,500'));
    expect(text, contains('消費税 ¥20,450'));
    expect(text, contains('請求合計 ¥224,950'));
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
          lines: [InvoiceLine(label: '作業', quantity: 1, unitPriceYen: 1000)],
        ),
      ],
    );

    final filename = InvoicePdfService.fileNameFor([unsafe]);

    expect(filename, endsWith('.pdf'));
    expect(filename, isNot(contains('/')));
  });

  test('annual PDF snapshot includes all invoices and title', () {
    final text = InvoicePdfService.buildTextSnapshot([
      invoice,
      invoice,
    ], title: '2026年 請求書');

    expect(text, contains('2026年 請求書'));
    expect(RegExp('株式会社テスト').allMatches(text).length, 2);
  });

  test('adopted invoice uses fixed 35-row paginated A4 layout', () {
    final pdf = File('lib/features/invoices/invoice_pdf_service.dart')
        .readAsStringSync();

    expect(pdf, contains('final detailPageCount ='));
    expect(pdf, contains('pageIndex * 35'));
    expect(pdf, contains('const gridBottom = 669.8898'));
    expect(pdf, contains('const rowHeight ='));
    expect(pdf, contains('regularFont ??'));
    expect(pdf, contains('Future<_InvoicePreviewData> _buildPreviewData()'));
    expect(pdf, contains('child: _InvoicePdfZoomView('));
    expect(pdf, contains('Printing.raster(widget.pdfBytes, dpi: 120)'));
    expect(pdf, contains('while (rows.length < 35)'));
    expect(pdf, isNot(contains('child: _ExactInvoiceScreen(')));
    expect(pdf, contains('請求書プレビューを生成できませんでした'));
    expect(pdf, contains('onLayout: (_) async => pdfBytes'));
    expect(pdf, contains('bytes: pdfBytes'));
  });
}

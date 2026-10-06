import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/domain/invoice_engine.dart';
import 'package:sk_works/features/invoices/invoice_pdf_service.dart';

void main() {
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

  test('dense 13-line invoice still builds a non-empty A4 PDF', () async {
    final denseInvoice = InvoiceEngine.calculate(
      customerId: '株式会社秀中',
      billingPeriod: '2026年10月',
      detailMode: InvoiceDetailMode.consolidatedOnly,
      sites: [
        SiteInvoiceCalculation(
          siteId: 'site-a',
          siteName: '（仮称）東京海上ビルディング計画',
          lines: List.generate(
            6,
            (index) => InvoiceLine(
              label: index == 0 ? '通常作業' : '追加項目$index',
              quantity: 1,
              unitPriceYen: 3000 + index * 100,
            ),
          ),
        ),
        SiteInvoiceCalculation(
          siteId: 'site-b',
          siteName: '江戸川清掃工場建て替え工事',
          lines: List.generate(
            7,
            (index) => InvoiceLine(
              label: index == 0 ? '通常作業' : '追加項目$index',
              quantity: 1,
              unitPriceYen: 4000 + index * 100,
            ),
          ),
        ),
      ],
      taxRateBps: 1000,
    );

    final bytes = await InvoicePdfService.buildPdf([denseInvoice]);

    expect(bytes, isNotEmpty);
    expect(bytes.length, greaterThan(1000));
  });

}

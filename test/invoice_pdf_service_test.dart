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

  test('invoice PDF HTML contains Japanese invoice content and totals', () {
    final html = InvoicePdfService.buildHtml([invoice]);

    expect(html, contains('請求書'));
    expect(html, contains('株式会社テスト'));
    expect(html, contains('新宿現場'));
    expect(html, contains('人工'));
    expect(html, contains('¥50,000'));
    expect(html, contains('請求合計'));
  });

  test('invoice PDF HTML escapes user-controlled text', () {
    final unsafe = InvoiceEngine.calculate(
      customerId: '<script>alert(1)</script>',
      billingPeriod: '2026年9月',
      detailMode: InvoiceDetailMode.consolidatedOnly,
      sites: const [
        SiteInvoiceCalculation(
          siteId: 'site-2',
          siteName: 'A&B',
          lines: [
            InvoiceLine(label: '<作業>', quantity: 1, unitPriceYen: 1000),
          ],
        ),
      ],
    );

    final html = InvoicePdfService.buildHtml([unsafe]);

    expect(html, isNot(contains('<script>alert(1)</script>')));
    expect(html, contains('&lt;script&gt;alert(1)&lt;/script&gt;'));
    expect(html, contains('A&amp;B'));
    expect(html, contains('&lt;作業&gt;'));
  });

  test('annual PDF inserts page breaks between invoices', () {
    final html = InvoicePdfService.buildHtml(
      [invoice, invoice],
      title: '2026年 請求書',
    );

    expect(RegExp('page-break').allMatches(html).length, greaterThanOrEqualTo(2));
    expect(html, contains('2026年 請求書'));
  });
}

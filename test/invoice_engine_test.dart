import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/domain/invoice_engine.dart';

void main() {
  test('saved welfare and tax rows do not enter the welfare base twice', () {
    final site = SiteInvoiceCalculation.fromSavedDetails(
      siteId: 'site',
      siteName: '現場',
      welfareRateBps: 300,
      subtotalYen: 103000,
      lines: const [
        InvoiceLine(label: '通常作業', quantity: 8, unitPriceYen: 12500),
        InvoiceLine(
          label: '（法定福利費）',
          workContent: '',
          quantity: 0,
          unitPriceYen: 0,
          amountYenOverride: 3000,
        ),
        InvoiceLine(
          label: '（消費税）',
          workContent: '',
          quantity: 0,
          unitPriceYen: 0,
          amountYenOverride: 10300,
        ),
      ],
    );
    expect(site.baseAmountYen, 100000);
    expect(site.welfareAmountYen, 3000);
    expect(site.subtotalYen, 103000);
    final invoice = InvoiceEngine.calculate(
      customerId: '登録会社',
      customerPhone: '03-1234-5678',
      billingPeriod: '2026年10月',
      detailMode: InvoiceDetailMode.consolidatedOnly,
      sites: [site],
    );
    expect(invoice.grandTotalYen, 113300);
    expect(invoice.customerPhone, '03-1234-5678');
    expect(site.lines.last.amountYen, 10300);
  });
  test(
    'recipient details are optional and pass through without fabrication',
    () {
      final blank = InvoiceEngine.calculate(
        customerId: '会社',
        billingPeriod: '2026年10月',
        detailMode: InvoiceDetailMode.consolidatedOnly,
        sites: const [],
      );
      expect(blank.customerPostalCode, isEmpty);
      expect(blank.customerAddress, isEmpty);
      final saved = InvoiceEngine.calculate(
        customerId: '会社',
        customerPostalCode: '100-0001',
        customerAddress: '東京都千代田区丸の内1丁目1-1',
        billingPeriod: '2026年10月',
        detailMode: InvoiceDetailMode.consolidatedOnly,
        sites: const [],
      );
      expect(saved.customerPostalCode, '100-0001');
      expect(saved.customerAddress, '東京都千代田区丸の内1丁目1-1');
    },
  );

  group('InvoiceEngine', () {
    test('rolls multiple site calculations into one invoice total', () {
      final result = InvoiceEngine.calculate(
        customerId: 'customer-1',
        billingPeriod: '2026-09',
        detailMode: InvoiceDetailMode.siteBreakdownOnInvoice,
        sites: const [
          SiteInvoiceCalculation(
            siteId: 'site-a',
            siteName: 'A現場',
            lines: [
              InvoiceLine(label: '通常人工', quantity: 10, unitPriceYen: 25000),
              InvoiceLine(label: '残業', quantity: 5, unitPriceYen: 3000),
            ],
          ),
          SiteInvoiceCalculation(
            siteId: 'site-b',
            siteName: 'B現場',
            lines: [
              InvoiceLine(label: '通常人工', quantity: 8, unitPriceYen: 25000),
              InvoiceLine(label: '追加工事', quantity: 1, unitPriceYen: 50000),
            ],
            manualAdjustmentYen: -5000,
          ),
        ],
      );

      expect(result.siteCalculations[0].subtotalYen, 265000);
      expect(result.siteCalculations[1].subtotalYen, 245000);
      expect(result.subtotalYen, 510000);
      expect(result.taxYen, 51000);
      expect(result.grandTotalYen, 561000);
    });

    test('adds welfare amount per site before invoice tax', () {
      final result = InvoiceEngine.calculate(
        customerId: 'customer-1',
        billingPeriod: '2026-09',
        detailMode: InvoiceDetailMode.siteDetailAttachment,
        sites: const [
          SiteInvoiceCalculation(
            siteId: 'site-a',
            siteName: 'A現場',
            welfareRateBps: 150,
            lines: [
              InvoiceLine(label: '一式工事', quantity: 1, unitPriceYen: 100000),
            ],
          ),
        ],
      );

      expect(result.siteCalculations.single.welfareAmountYen, 1500);
      expect(result.subtotalYen, 101500);
      expect(result.taxYen, 10150);
      expect(result.grandTotalYen, 111650);
    });

    test('rounds fractional line totals to whole yen', () {
      const line = InvoiceLine(
        label: '半人工',
        quantity: 0.5,
        unitPriceYen: 25001,
      );

      expect(line.amountYen, 12501);
    });

    test('allows zero-value automatic drafts without sites', () {
      final result = InvoiceEngine.calculate(
        customerId: '取引先未設定（自動下書き）',
        billingPeriod: '2026-09',
        detailMode: InvoiceDetailMode.consolidatedOnly,
        sites: const [],
      );

      expect(result.siteCalculations, isEmpty);
      expect(result.subtotalYen, 0);
      expect(result.taxYen, 0);
      expect(result.grandTotalYen, 0);
    });
  });

  test('InvoiceEngine accepts primary invoice row with site label and blank work content', () {
    final result = InvoiceEngine.calculate(
      customerId: '株式会社 秀中',
      billingPeriod: '2026年10月',
      detailMode: InvoiceDetailMode.siteBreakdownOnInvoice,
      sites: const [
        SiteInvoiceCalculation(
          siteId: 'site-1',
          siteName: '江戸川清掃工場建て替え工事',
          lines: [
            InvoiceLine(
              label: '',
              siteLabel: '江戸川清掃工場建て替え工事',
              workContent: '',
              quantity: 1,
              unitPriceYen: 32800,
            ),
          ],
        ),
      ],
    );

    expect(result.grandTotalYen, greaterThan(0));
  });
}

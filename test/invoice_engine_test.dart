import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/domain/invoice_engine.dart';

void main() {
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

    test('rejects invoices without sites', () {
      expect(
        () => InvoiceEngine.calculate(
          customerId: 'customer-1',
          billingPeriod: '2026-09',
          detailMode: InvoiceDetailMode.consolidatedOnly,
          sites: const [],
        ),
        throwsArgumentError,
      );
    });
  });
}

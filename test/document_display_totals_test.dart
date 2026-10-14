import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/domain/invoice_engine.dart';
import 'package:sk_works/features/shared/document_display_totals.dart';

void main() {
  test('saved charge rows are hidden without recalculating the invoice', () {
    final site = SiteInvoiceCalculation.fromSavedDetails(siteId: 'a', siteName: '現場',
      welfareRateBps: 1500, subtotalYen: 37720, lines: const [
        InvoiceLine(label: '作業', quantity: 1, unitPriceYen: 32800),
        InvoiceLine(label: '（法定福利費）', quantity: 0, unitPriceYen: 0, amountYenOverride: 4920),
        InvoiceLine(label: '（消費税）', quantity: 0, unitPriceYen: 0, amountYenOverride: 3772),
      ]);
    final invoice = InvoiceEngine.calculate(customerId: '顧客', billingPeriod: '2026年10月',
      detailMode: InvoiceDetailMode.siteBreakdownOnInvoice, sites: [site],
      subtotalYenOverride: 37720, taxYenOverride: 3772, grandTotalYenOverride: 41492);
    final display = DocumentDisplayTotals.invoice(invoice);
    expect([display.workSubtotal, display.welfare, display.tax, display.total], [32800, 4920, 3772, 41492]);
    expect(site.lines.where((line) => !isInvoiceChargeLine(line)), hasLength(1));
    expect(invoice.siteCalculations.single.lines, hasLength(3));
  });
  test('multiple historical rates are summed rather than applying one new rate', () {
    final invoice = InvoiceEngine.calculate(customerId: '顧客', billingPeriod: '月',
      detailMode: InvoiceDetailMode.siteBreakdownOnInvoice, sites: const [
        SiteInvoiceCalculation(siteId: 'a', siteName: 'A', welfareRateBps: 300,
          lines: [InvoiceLine(label: '作業', quantity: 1, unitPriceYen: 100000)]),
        SiteInvoiceCalculation(siteId: 'b', siteName: 'B', welfareRateBps: 150,
          lines: [InvoiceLine(label: '作業', quantity: 1, unitPriceYen: 100000)]),
      ]);
    final totals = DocumentDisplayTotals.invoice(invoice);
    expect([totals.workSubtotal, totals.welfare, totals.tax, totals.total], [200000, 4500, 20450, 224950]);
  });
  test('classification does not hide ordinary expense or allowance descriptions', () {
    expect(isDocumentTaxLabel('（消費税）'), true);
    expect(isDocumentWelfareLabel('福利厚生費（15%）'), true);
    expect(isDocumentWelfareLabel('福利厚生費補助'), false);
    expect(isDocumentTaxLabel('消費税調整手当'), false);
  });
}

import '../../domain/invoice_engine.dart';

String _chargeLabel(String value) => value
    .replaceAll(RegExp(r'[（）()\s]'), '').replaceAll('％', '%');
bool isDocumentWelfareLabel(String value) => RegExp(
  r'^(?:法定福利費|福利厚生費)(?:[0-9.,]+%)?$').hasMatch(_chargeLabel(value));
bool isDocumentTaxLabel(String value) => RegExp(
  r'^消費税(?:[0-9.,]+%)?$').hasMatch(_chargeLabel(value));
bool isInvoiceChargeLine(InvoiceLine line) =>
  line.category == 'welfare' || line.category == 'tax' ||
  isDocumentWelfareLabel(line.displayWorkContent) || isDocumentTaxLabel(line.displayWorkContent);

/// Presentation only. Never recalculate saved taxes, rates or document totals.
class DocumentDisplayTotals {
  const DocumentDisplayTotals({required this.workSubtotal, required this.welfare,
    required this.tax, required this.total});
  factory DocumentDisplayTotals.invoice(InvoiceCalculationResult invoice) {
    final welfare = invoice.siteCalculations.fold<int>(0, (sum, site) => sum + site.welfareAmountYen);
    return DocumentDisplayTotals(workSubtotal: invoice.subtotalYen - welfare + invoice.expenseExtraAmountYen,
      welfare: welfare, tax: invoice.taxYen, total: invoice.grandTotalYen);
  }
  final int workSubtotal, welfare, tax, total;
}

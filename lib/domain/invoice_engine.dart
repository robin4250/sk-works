enum InvoiceDetailMode {
  consolidatedOnly,
  siteBreakdownOnInvoice,
  siteDetailAttachment,
}

class InvoiceLine {
  const InvoiceLine({
    required this.label,
    required this.quantity,
    required this.unitPriceYen,
  });

  final String label;
  final double quantity;
  final int unitPriceYen;

  int get amountYen => (quantity * unitPriceYen).round();
}

class SiteInvoiceCalculation {
  const SiteInvoiceCalculation({
    required this.siteId,
    required this.siteName,
    required this.lines,
    this.manualAdjustmentYen = 0,
    this.welfareRateBps = 0,
  });

  final String siteId;
  final String siteName;
  final List<InvoiceLine> lines;
  final int manualAdjustmentYen;

  /// Basis points. Example: 150 = 1.5%.
  final int welfareRateBps;

  int get baseAmountYen =>
      lines.fold<int>(0, (sum, line) => sum + line.amountYen) +
      manualAdjustmentYen;

  int get welfareAmountYen =>
      (baseAmountYen * welfareRateBps / 10000).round();

  int get subtotalYen => baseAmountYen + welfareAmountYen;
}

class InvoiceCalculationResult {
  const InvoiceCalculationResult({
    required this.customerId,
    required this.billingPeriod,
    required this.detailMode,
    required this.siteCalculations,
    required this.taxRateBps,
  });

  final String customerId;
  final String billingPeriod;
  final InvoiceDetailMode detailMode;
  final List<SiteInvoiceCalculation> siteCalculations;

  /// Basis points. Example: 1000 = 10%.
  final int taxRateBps;

  int get subtotalYen => siteCalculations.fold<int>(
        0,
        (sum, site) => sum + site.subtotalYen,
      );

  int get taxYen => (subtotalYen * taxRateBps / 10000).round();

  int get grandTotalYen => subtotalYen + taxYen;
}

class InvoiceEngine {
  const InvoiceEngine._();

  static InvoiceCalculationResult calculate({
    required String customerId,
    required String billingPeriod,
    required InvoiceDetailMode detailMode,
    required List<SiteInvoiceCalculation> sites,
    int taxRateBps = 1000,
  }) {
    if (customerId.trim().isEmpty) {
      throw ArgumentError.value(customerId, 'customerId', 'must not be empty');
    }
    if (billingPeriod.trim().isEmpty) {
      throw ArgumentError.value(
        billingPeriod,
        'billingPeriod',
        'must not be empty',
      );
    }
    if (sites.isEmpty) {
      throw ArgumentError.value(sites, 'sites', 'must contain at least one site');
    }
    if (taxRateBps < 0) {
      throw ArgumentError.value(taxRateBps, 'taxRateBps', 'must be >= 0');
    }

    for (final site in sites) {
      if (site.siteId.trim().isEmpty) {
        throw ArgumentError('siteId must not be empty');
      }
      if (site.siteName.trim().isEmpty) {
        throw ArgumentError('siteName must not be empty');
      }
      if (site.welfareRateBps < 0) {
        throw ArgumentError('welfareRateBps must be >= 0');
      }
      for (final line in site.lines) {
        if (line.label.trim().isEmpty) {
          throw ArgumentError('line label must not be empty');
        }
        if (line.quantity < 0) {
          throw ArgumentError('line quantity must be >= 0');
        }
      }
    }

    return InvoiceCalculationResult(
      customerId: customerId,
      billingPeriod: billingPeriod,
      detailMode: detailMode,
      siteCalculations: List.unmodifiable(sites),
      taxRateBps: taxRateBps,
    );
  }
}

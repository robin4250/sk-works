/// Site-specific amounts for area work and a freely agreed contract price.
/// This calculation is independent of attendance and wage premium formulas.
enum SitePaymentMode { squareMetre, lumpSum }

enum SitePaymentAdjustmentDirection { addition, deduction }

class SitePaymentAdjustment {
  SitePaymentAdjustment({
    required this.id,
    required this.name,
    required this.amountYen,
    required this.direction,
  }) {
    if (id.trim().isEmpty || name.trim().isEmpty || amountYen < 0) {
      throw ArgumentError('追加項目の識別子・名称・非負の金額が必要です。');
    }
  }

  final String id;
  final String name;
  final int amountYen;
  final SitePaymentAdjustmentDirection direction;
  int get signedAmountYen =>
      direction == SitePaymentAdjustmentDirection.addition
          ? amountYen
          : -amountYen;
}

class SitePaymentTerms {
  SitePaymentTerms({
    required this.siteId,
    required this.parentCompanyId,
    required this.subcontractorCompanyId,
    required this.mode,
    required this.baseAmountYen,
    required this.taxIncluded,
    required this.taxAmountYen,
    required this.taxRateBasisPoints,
    required this.taxableAmountYen,
    required this.roundingRule,
    this.squareMetreUnitPriceYen,
    this.areaHundredths,
    List<SitePaymentAdjustment> adjustments = const [],
  }) : adjustments = List.unmodifiable(adjustments) {
    if (siteId.isEmpty || parentCompanyId.isEmpty ||
        subcontractorCompanyId.isEmpty ||
        parentCompanyId == subcontractorCompanyId ||
        baseAmountYen < 0 || taxAmountYen < 0 ||
        taxRateBasisPoints < 0 || taxableAmountYen < 0 ||
        roundingRule.isEmpty) {
      throw ArgumentError('現場・双方会社・金額・税条件が必要です。');
    }
    if (this.adjustments.map((item) => item.id).toSet().length !=
        this.adjustments.length) {
      throw ArgumentError('追加項目の識別子が重複しています。');
    }
    if (mode == SitePaymentMode.squareMetre) {
      final price = squareMetreUnitPriceYen;
      final area = areaHundredths;
      if (price == null || area == null || price < 0 || area < 0) {
        throw ArgumentError('平米単価と平米数が必要です。');
      }
      // Do not guess the company's fraction-of-yen rounding policy.
      if ((price * area) % 100 != 0 || baseAmountYen != price * area ~/ 100) {
        throw ArgumentError('平米計算の総額が一致しないか、端数処理が必要です。');
      }
    } else if (squareMetreUnitPriceYen != null || areaHundredths != null) {
      throw ArgumentError('請負額に平米計算の数量は使用しません。');
    }
  }

  final String siteId;
  final String parentCompanyId;
  final String subcontractorCompanyId;
  final SitePaymentMode mode;
  final int baseAmountYen;
  final int? squareMetreUnitPriceYen;
  /// Hundredths of a square metre, avoiding binary floating point money.
  final int? areaHundredths;
  final List<SitePaymentAdjustment> adjustments;
  final bool taxIncluded;
  final int taxAmountYen;
  final int taxRateBasisPoints;
  final int taxableAmountYen;
  final String roundingRule;

  int get finalAmountYen => baseAmountYen +
      adjustments.fold<int>(0, (sum, item) => sum + item.signedAmountYen) +
      (taxIncluded ? 0 : taxAmountYen);

  /// Compares both originals. Matching values alone never imply approval.
  List<String> differencesFrom(SitePaymentTerms other) {
    final differences = <String>[];
    void compare(String key, Object? left, Object? right) {
      if (left != right) differences.add(key);
    }
    compare('site_id', siteId, other.siteId);
    compare('parent_company_id', parentCompanyId, other.parentCompanyId);
    compare('subcontractor_company_id', subcontractorCompanyId,
        other.subcontractorCompanyId);
    compare('mode', mode, other.mode);
    compare('base_amount_yen', baseAmountYen, other.baseAmountYen);
    compare('square_metre_unit_price_yen', squareMetreUnitPriceYen,
        other.squareMetreUnitPriceYen);
    compare('area_hundredths', areaHundredths, other.areaHundredths);
    compare('tax_included', taxIncluded, other.taxIncluded);
    compare('tax_amount_yen', taxAmountYen, other.taxAmountYen);
    compare('tax_rate_basis_points', taxRateBasisPoints, other.taxRateBasisPoints);
    compare('taxable_amount_yen', taxableAmountYen, other.taxableAmountYen);
    compare('rounding_rule', roundingRule, other.roundingRule);
    final own = {for (final item in adjustments) item.id: item};
    final theirs = {for (final item in other.adjustments) item.id: item};
    for (final id in {...own.keys, ...theirs.keys}) {
      final left = own[id];
      final right = theirs[id];
      if (left == null || right == null || left.name != right.name ||
          left.amountYen != right.amountYen || left.direction != right.direction) {
        differences.add('adjustment:$id');
      }
    }
    compare('final_amount_yen', finalAmountYen, other.finalAmountYen);
    return List.unmodifiable(differences);
  }
}

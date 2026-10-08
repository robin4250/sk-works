import 'package:flutter_test/flutter_test.dart';
import '../lib/features/payroll/payment_certificate_site_terms.dart';

SitePaymentTerms terms({
  int unitPrice = 1200,
  int area = 1250,
  int? base,
  bool included = false,
  int tax = 1500,
  List<SitePaymentAdjustment> adjustments = const [],
}) => SitePaymentTerms(
  siteId: 'site', parentCompanyId: 'parent', subcontractorCompanyId: 'child',
  mode: SitePaymentMode.squareMetre, baseAmountYen: base ?? unitPrice * area ~/ 100,
  squareMetreUnitPriceYen: unitPrice, areaHundredths: area,
  taxIncluded: included, taxAmountYen: tax, taxRateBasisPoints: 1000,
  taxableAmountYen: 15000, roundingRule: 'floor', adjustments: adjustments,
);

void main() {
  test('area amount and extras have no attendance premium input', () {
    final value = terms(adjustments: [
      SitePaymentAdjustment(id: 'extra', name: '追加工事', amountYen: 2000,
          direction: SitePaymentAdjustmentDirection.addition),
      SitePaymentAdjustment(id: 'welfare', name: '福利厚生費', amountYen: 500,
          direction: SitePaymentAdjustmentDirection.deduction),
    ]);
    expect(value.baseAmountYen, 15000);
    expect(value.finalAmountYen, 18000);
  });
  test('included tax is not added again', () {
    expect(terms(included: true).finalAmountYen, 15000);
  });
  test('equal total does not hide different price and quantity', () {
    final differences = terms().differencesFrom(terms(unitPrice: 1500, area: 1000));
    expect(differences, contains('square_metre_unit_price_yen'));
    expect(differences, contains('area_hundredths'));
    expect(differences, isNot(contains('final_amount_yen')));
  });
  test('tax handling is compared even when final amount matches', () {
    expect(terms(tax: 0).differencesFrom(terms(included: true, tax: 0)),
        contains('tax_included'));
  });
  test('lump sum uses freely entered amount without area', () {
    final value = SitePaymentTerms(
      siteId: 'site', parentCompanyId: 'parent', subcontractorCompanyId: 'child',
      mode: SitePaymentMode.lumpSum, baseAmountYen: 123456,
      taxIncluded: true, taxAmountYen: 0, taxRateBasisPoints: 0,
      taxableAmountYen: 0, roundingRule: 'floor',
    );
    expect(value.finalAmountYen, 123456);
  });
  test('invalid area total and ambiguous fractional yen are rejected', () {
    expect(() => terms(base: 42), throwsArgumentError);
    expect(() => terms(unitPrice: 1, area: 1), throwsArgumentError);
  });
  test('original extras are immutable and duplicate identities are rejected', () {
    final extra = SitePaymentAdjustment(id: 'a', name: '追加', amountYen: 100,
        direction: SitePaymentAdjustmentDirection.addition);
    final mutable = [extra];
    final value = terms(adjustments: mutable);
    mutable.clear();
    expect(value.adjustments, hasLength(1));
    expect(() => value.adjustments.clear(), throwsUnsupportedError);
    expect(() => terms(adjustments: [extra, extra]), throwsArgumentError);
  });
}

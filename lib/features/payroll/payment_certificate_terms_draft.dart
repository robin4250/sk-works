import '../../domain/rate_formula_settings.dart';

enum CertificatePayBasis { hourly, daily, monthly, contract }
enum CertificateItemDirection { payment, deduction }
enum CertificateItemUnit { hour, day, month }

class CertificateBasisTerms {
  const CertificateBasisTerms({this.amountYen=0,this.calculationDailyYen=0,
    this.formula=const RateFormulaSettings()});
  final int amountYen;
  final int calculationDailyYen;
  final RateFormulaSettings formula;
  int calculationInput(CertificatePayBasis basis) =>
    basis==CertificatePayBasis.monthly || basis==CertificatePayBasis.contract
      ? calculationDailyYen : amountYen;
  int overtimeRate(CertificatePayBasis basis) => formula.overtime(
    calculationInput(basis),hourlyBase:basis==CertificatePayBasis.hourly);
}
class CertificateUnitItem {
  const CertificateUnitItem({required this.id,required this.basis,
    required this.direction,required this.unit,required this.name,required this.amountYen});
  final String id;
  final CertificatePayBasis basis;
  final CertificateItemDirection direction;
  final CertificateItemUnit unit;
  final String name;
  final int amountYen;
}
/// Editing contract only. Legacy per-selection allowance quantities are retained
/// by the persistence adapter, never inferred as hours/days/months by this UI.
class CertificateTermsDraft {
  CertificateTermsDraft({this.selectedBasis=CertificatePayBasis.daily,
    Map<CertificatePayBasis,CertificateBasisTerms> bases=const {},
    List<CertificateUnitItem> items=const [],this.welfarePercent=0,this.taxPercent=10})
    :bases=Map.unmodifiable({for(final b in CertificatePayBasis.values)
      b:bases[b]??const CertificateBasisTerms()}),items=List.unmodifiable(items);
  final CertificatePayBasis selectedBasis;
  final Map<CertificatePayBasis,CertificateBasisTerms> bases;
  final List<CertificateUnitItem> items;
  final double welfarePercent;
  final double taxPercent;
}

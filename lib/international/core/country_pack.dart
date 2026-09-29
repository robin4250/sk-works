class CountryPack {
  const CountryPack({
    required this.countryCode,
    required this.languageCode,
    required this.currencyCode,
    required this.datePattern,
    required this.phoneCountryCode,
    required this.legalDocumentKeys,
  });

  final String countryCode;
  final String languageCode;
  final String currencyCode;
  final String datePattern;
  final String phoneCountryCode;
  final List<String> legalDocumentKeys;
}

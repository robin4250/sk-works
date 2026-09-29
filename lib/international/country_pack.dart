/// Country-specific configuration kept behind one replaceable pack.
///
/// Feature code should depend on this contract rather than hard-coding Japan
/// formats, so future country packs can swap language/legal presentation
/// without forking core SKO workflows.
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

const japanCountryPack = CountryPack(
  countryCode: 'JP',
  languageCode: 'ja',
  currencyCode: 'JPY',
  datePattern: 'yyyy/MM/dd',
  phoneCountryCode: '+81',
  legalDocumentKeys: <String>[
    'my_number_card',
    'employment_documents',
    'qualification_certificates',
  ],
);

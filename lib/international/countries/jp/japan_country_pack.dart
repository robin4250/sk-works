import '../../core/country_pack.dart';

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

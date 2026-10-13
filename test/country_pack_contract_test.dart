import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/international/country_pack.dart';

void main() {
  test('country pack keeps regional differences outside core features', () {
    expect(japanCountryPack.countryCode, 'JP');
    expect(japanCountryPack.languageCode, 'ja');
    expect(japanCountryPack.currencyCode, 'JPY');
    expect(japanCountryPack.phoneCountryCode, '+81');
    expect(japanCountryPack.legalDocumentKeys, contains('my_number_card'));
  });

  test('legacy import surface is only a compatibility shim', () {
    // If this compiles, older imports still resolve while the implementation
    // remains in core/country_pack.dart + countries/jp.
    expect(japanCountryPack.datePattern, 'yyyy/MM/dd');
  });
}

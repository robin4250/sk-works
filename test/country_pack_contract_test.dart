import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('country pack keeps regional differences outside core features', () {
    final source =
        File('lib/international/country_pack.dart').readAsStringSync();

    expect(source, contains('class CountryPack'));
    expect(source, contains("countryCode: 'JP'"));
    expect(source, contains("languageCode: 'ja'"));
    expect(source, contains("currencyCode: 'JPY'"));
    expect(source, contains("phoneCountryCode: '+81'"));
    expect(source, contains('legalDocumentKeys'));
  });
}

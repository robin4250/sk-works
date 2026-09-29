import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/international/country_pack_registry.dart';

void main() {
  test('known Japan selection resolves normally', () {
    expect(CountryPackRegistry.resolve('JP').countryCode, 'JP');
    expect(CountryPackRegistry.resolve('jp').countryCode, 'JP');
  });

  test('unknown or missing country never blocks startup', () {
    expect(CountryPackRegistry.resolve(null).countryCode, 'JP');
    expect(CountryPackRegistry.resolve('').countryCode, 'JP');
    expect(CountryPackRegistry.resolve('UNKNOWN').countryCode, 'JP');
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/international/market_selection.dart';

void main() {
  test('language and country are selected independently', () {
    final selection = MarketSelection.fromDeviceLocale(
      languageCode: 'ja-JP',
      countryCode: 'JP',
    );
    expect(selection.language.languageCode, 'ja');
    expect(selection.country.countryCode, 'JP');
  });

  test('unsupported locale safely falls back without blocking startup', () {
    final selection = MarketSelection.fromDeviceLocale(
      languageCode: 'xx',
      countryCode: 'ZZ',
    );
    expect(selection.language.languageCode, 'ja');
    expect(selection.country.countryCode, 'JP');
  });
}

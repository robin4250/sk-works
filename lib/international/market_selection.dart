import 'core/country_pack.dart';
import 'core/language_pack.dart';
import 'country_pack_registry.dart';
import 'language_pack_registry.dart';

class MarketSelection {
  const MarketSelection({
    required this.country,
    required this.language,
  });

  final CountryPack country;
  final LanguagePack language;

  /// Device locale is a suggestion for first-run UX, never an authorization
  /// decision and never a permanent country assignment.
  static MarketSelection fromDeviceLocale({
    required String? languageCode,
    required String? countryCode,
  }) {
    return MarketSelection(
      country: CountryPackRegistry.resolve(countryCode),
      language: LanguagePackRegistry.resolve(languageCode),
    );
  }
}

import 'active_country_pack.dart';
import 'core/country_pack.dart';
import 'countries/jp/japan_country_pack.dart';

class CountryPackRegistry {
  const CountryPackRegistry._();

  static const Map<String, CountryPack> supported = <String, CountryPack>{
    'JP': japanCountryPack,
  };

  /// Never returns null. Unknown, empty, or malformed country selections fall
  /// back to the current production pack instead of blocking app startup.
  static CountryPack resolve(String? countryCode) {
    final normalized = countryCode?.trim().toUpperCase();
    if (normalized == null || normalized.isEmpty) return activeCountryPack;
    return supported[normalized] ?? activeCountryPack;
  }
}

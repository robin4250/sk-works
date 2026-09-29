import 'core/country_pack.dart';
import 'countries/jp/japan_country_pack.dart';

/// Current production country pack.
///
/// Japan is the production default today. Future country launches should add a
/// sibling folder under countries/ and switch selection here (or via remote
/// configuration) without forking core features.
const CountryPack activeCountryPack = japanCountryPack;

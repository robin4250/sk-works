// Backward-compatible import surface.
//
// The canonical contract lives in core/country_pack.dart and Japan-specific
// values live under countries/jp. Keep this file as a compatibility export so
// older feature imports continue to build while regional logic has one source
// of truth.
export 'core/country_pack.dart';
export 'countries/jp/japan_country_pack.dart' show japanCountryPack;

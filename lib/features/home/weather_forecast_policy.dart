enum WeatherAddressKind { company, home, site, unavailable }

enum WeatherProvider { openWeather, appleWeatherKit }

class WeatherAddressSelection {
  const WeatherAddressSelection(this.kind, this.address);
  final WeatherAddressKind kind;
  final String? address;
}

/// Uses registered addresses only; no GPS, geocoding or database writes.
WeatherAddressSelection selectWeatherAddress({
  required String? companyAddress,
  required String? homeAddress,
  required String? activeSiteAddress,
  required bool working,
  required bool isAdministrator,
}) {
  String? clean(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();
  final company = clean(companyAddress);
  final home = clean(homeAddress);
  final site = clean(activeSiteAddress);
  if (isAdministrator) {
    return WeatherAddressSelection(
      company == null
          ? WeatherAddressKind.unavailable
          : WeatherAddressKind.company,
      company,
    );
  }
  // Until the employee registers a home address, use the company area.
  if (home == null) {
    return WeatherAddressSelection(
      company == null
          ? WeatherAddressKind.unavailable
          : WeatherAddressKind.company,
      company,
    );
  }
  if (!working) {
    return WeatherAddressSelection(WeatherAddressKind.home, home);
  }
  // Missing site data must not silently display the weather at home or company.
  return WeatherAddressSelection(
    site == null ? WeatherAddressKind.unavailable : WeatherAddressKind.site,
    site,
  );
}

/// Provider choice must also be checked server-side before persisting it.
bool canChooseWeatherProvider({required bool isMasterAdministrator}) =>
    isMasterAdministrator;

const weatherForecastHours = [0, 3, 6, 9, 12, 15, 18, 21, 24];

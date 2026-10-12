import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/home/weather_forecast_gateway.dart';

void main() {
  test('minute precipitation uses sourced future time; missing/stale/malformed does not become rain-free', () {
    Map<String, dynamic> today() => {
      'contract_version': 1, 'day_offset': 0, 'base_date': '2026-10-12',
      'forecast_date': '2026-10-12', 'time_zone': 'Asia/Tokyo', 'source': 'OpenWeather',
      'region_kind': 'company', 'location_label': 'company', 'checked_at': '2026-10-12T00:00:00Z',
      'attribution': {'name': 'OpenWeather', 'url': 'https://openweathermap.org/'},
      'summary_kind': 'unavailable',
      'hours': List.generate(9, (i) => {'hour': i * 3}),
      'rain_approach': {'forecast_at': '2026-10-12T00:05:00Z', 'reference_at': '2026-10-12T00:00:00Z',
        'local_hour': 9, 'local_minute': 5, 'precipitation_mm_per_hour': 1.2, 'source': 'OpenWeather'},
    };
    final result = WeatherGatewayResult.parse(today(), 0);
    expect(result.snapshot.rainForecastAt, DateTime.utc(2026, 10, 12, 0, 5));
    expect(result.snapshot.updatedAt, DateTime.parse('2026-10-12T00:00:00Z').toLocal());
    expect(result.snapshot.updatedAt.isUtc, isFalse);
    final missing = today()..['rain_approach'] = null;
    expect(WeatherGatewayResult.parse(missing, 0).snapshot.rainForecastAt, isNull);
    for (final change in ['forecast_at','reference_at','local_minute','precipitation_mm_per_hour','source']) {
      final data = today();
      final rain = data['rain_approach'] as Map<String, dynamic>;
      rain[change] = switch (change) {
        'forecast_at' => '2026-10-12T01:01:00Z',
        'reference_at' => '2026-10-11T23:40:00Z',
        'local_minute' => 60,
        'precipitation_mm_per_hour' => 0,
        _ => 'unknown',
      };
      expect(() => WeatherGatewayResult.parse(data, 0), throwsFormatException);
    }
  });

  Map<String, dynamic> payload() => {
    'contract_version': 1, 'day_offset': 2, 'base_date': '2026-10-12',
    'forecast_date': '2026-10-14', 'time_zone': 'Asia/Tokyo', 'source': 'OpenWeather',
    'location_label': 'registered area', 'region_kind': 'company', 'checked_at': '2026-10-12T00:00:00Z',
    'attribution': {'name': 'OpenWeather', 'url': 'https://openweathermap.org/'}, 'current_temperature_celsius': null, 'summary_kind': 'unavailable',
    'hours': List.generate(9, (i) => {'hour': i * 3, 'temperature_celsius': i == 0 ? 10.5 : null,
      'precipitation_probability_percent': i == 0 ? 20.0 : null}),
  };
  test('gateway calendar comes from region and unavailable values remain null', () {
    final result = WeatherGatewayResult.parse(payload(), 2);
    expect(result.baseDate, DateTime(2026, 10, 12));
    expect(result.snapshot.forecastDate, DateTime(2026, 10, 14));
    expect(result.snapshot.currentTemperatureCelsius, isNull);
    expect(result.snapshot.hours.first.temperatureCelsius, 10.5);
    expect(result.snapshot.hours[8].rainProbability, isNull);
  });
  test('future summary has an explicit source hour and condition mapping', () {
    final data = payload();
    data['summary_kind'] = 'forecast_hour'; data['summary_hour'] = 0;
    data['summary_temperature_celsius'] = 10.5; data['summary_condition'] = 'weatherkit:Rain';
    final result = WeatherGatewayResult.parse(data, 2);
    expect(result.snapshot.forecastSummaryHour, 0);
    expect(result.snapshot.forecastSummaryTemperatureCelsius, 10.5);
    expect(result.snapshot.currentTemperatureCelsius, isNull);
    expect(weatherCondition('openweather:800').label, '晴れ');
    expect(weatherCondition('weatherkit:Snow').label, '雪');
    expect(weatherCondition('openweather:741').label, '霧');
    expect(weatherCondition('openweather:781').label, '未取得');
    expect(weatherCondition('openweather:751').label, '未取得');
    expect(weatherCondition('openweather:450').label, '未取得');
    data['summary_hour'] = 24;
    expect(() => WeatherGatewayResult.parse(data, 2), throwsFormatException);
    data['summary_hour'] = 0; data['attribution'] = {'name': 'Apple Weather', 'url': 'https://untrusted.invalid/'};
    expect(() => WeatherGatewayResult.parse(data, 2), throwsFormatException);
  });
  test('gateway rejects a wrong day, malformed calendar, invalid percentage and slot reuse', () {
    for (final change in ['forecast_date', 'base_date', 'chance', 'hour']) {
      final data = payload();
      if (change == 'forecast_date') { data[change] = '2026-10-13'; }
      if (change == 'base_date') { data[change] = '2026-02-31'; }
      if (change == 'chance') { data['hours'][0]['precipitation_probability_percent'] = 120; }
      if (change == 'hour') { data['hours'][8]['hour'] = 0; }
      expect(() => WeatherGatewayResult.parse(data, 2), throwsFormatException);
    }
    expect(() => WeatherGatewayResult.parse(payload(), 1), throwsFormatException);
  });
}


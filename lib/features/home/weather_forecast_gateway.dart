import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../international/language_controller.dart';
import 'weather_forecast_card.dart';
import 'weather_forecast_controller.dart';

({String label, IconData icon}) weatherCondition(dynamic code) {
  final text = code?.toString() ?? '';
  final id = text.startsWith('openweather:')
      ? int.tryParse(text.substring(12))
      : null;
  String label = '未取得';
  IconData icon = Icons.cloud_outlined;
  if (id == 800 ||
      text == 'weatherkit:Clear' ||
      text == 'weatherkit:MostlyClear') {
    label = '晴れ';
    icon = Icons.wb_sunny_outlined;
  } else if ((id != null && id >= 801 && id <= 804) ||
      [
        'weatherkit:Cloudy',
        'weatherkit:MostlyCloudy',
        'weatherkit:PartlyCloudy',
      ].contains(text)) {
    label = '曇り';
  } else if ([200, 201, 202, 210, 211, 212, 221, 230, 231, 232].contains(id) ||
      [
        'weatherkit:Thunderstorms',
        'weatherkit:ScatteredThunderstorms',
        'weatherkit:StrongStorms',
      ].contains(text)) {
    label = '雷';
    icon = Icons.thunderstorm_outlined;
  } else if ([
        300,
        301,
        302,
        310,
        311,
        312,
        313,
        314,
        321,
        500,
        501,
        502,
        503,
        504,
        511,
        520,
        521,
        522,
        531,
      ].contains(id) ||
      [
        'weatherkit:Rain',
        'weatherkit:Drizzle',
        'weatherkit:HeavyRain',
        'weatherkit:SunShowers',
      ].contains(text)) {
    label = '雨';
    icon = Icons.water_drop_outlined;
  } else if ([
        600,
        601,
        602,
        611,
        612,
        613,
        615,
        616,
        620,
        621,
        622,
      ].contains(id) ||
      [
        'weatherkit:Snow',
        'weatherkit:Flurries',
        'weatherkit:HeavySnow',
        'weatherkit:Blizzard',
        'weatherkit:Sleet',
        'weatherkit:SunFlurries',
      ].contains(text)) {
    label = '雪';
    icon = Icons.ac_unit;
  } else if ([701, 711, 721, 741].contains(id) ||
      [
        'weatherkit:Foggy',
        'weatherkit:Haze',
        'weatherkit:Smoky',
      ].contains(text)) {
    label = '霧';
    icon = Icons.blur_on;
  }
  return (label: SkoLanguageController.tr(label), icon: icon);
}

/// Offset requests avoid substituting the device calendar for the region's day.
class WeatherGatewayResult {
  const WeatherGatewayResult({
    required this.baseDate,
    required this.dayOffset,
    required this.timeZone,
    required this.regionKind,
    required this.snapshot,
    required this.attribution,
    this.radarUri,
  });
  final DateTime baseDate;
  final int dayOffset;
  final String timeZone;
  final String regionKind;
  final Uri? radarUri;
  final WeatherForecastSnapshot snapshot;
  final Map<String, dynamic> attribution;

  factory WeatherGatewayResult.parse(dynamic raw, int expectedOffset) {
    if (raw is! Map ||
        raw['contract_version'] != 1 ||
        raw['day_offset'] != expectedOffset ||
        raw['time_zone'] is! String ||
        (raw['time_zone'] as String).isEmpty ||
        raw['source'] is! String ||
        raw['location_label'] is! String ||
        raw['attribution'] is! Map ||
        !['company', 'home', 'site'].contains(raw['region_kind'])) {
      throw const FormatException('Weather contract unavailable');
    }
    DateTime date(dynamic value) {
      if (value is! String ||
          !RegExp(r'^20\d{2}-\d{2}-\d{2}$').hasMatch(value)) {
        throw const FormatException('Weather calendar unavailable');
      }
      final parsed = DateTime.parse(value);
      if (parsed.toIso8601String().substring(0, 10) != value) {
        throw const FormatException('Weather calendar unavailable');
      }
      return parsed;
    }

    final radarUri = raw['radar_url'] == null
        ? null
        : Uri.tryParse(raw['radar_url'].toString());
    if (radarUri != null &&
        (raw['country_code'] != 'JP' ||
            radarUri.scheme != 'https' ||
            radarUri.host != 'weather.yahoo.co.jp' ||
            radarUri.userInfo.isNotEmpty)) {
      throw const FormatException('Weather radar unavailable');
    }
    final attribution = Map<String, dynamic>.from(raw['attribution']);
    for (final key in ['url', 'logo_light_url', 'logo_dark_url']) {
      if (attribution[key] == null && key != 'url') {
        continue;
      }
      final uri = Uri.tryParse(attribution[key]?.toString() ?? '');
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.userInfo.isNotEmpty ||
          !['weatherkit.apple.com', 'openweathermap.org'].contains(uri.host)) {
        throw const FormatException('Weather attribution unavailable');
      }
    }
    if (attribution['trademark_required'] == true &&
        (attribution['logo_light_url'] == null ||
            attribution['logo_dark_url'] == null)) {
      throw const FormatException('Weather attribution unavailable');
    }
    final base = date(raw['base_date']), forecast = date(raw['forecast_date']);
    if (DateTime(base.year, base.month, base.day + expectedOffset) !=
        forecast) {
      throw const FormatException('Weather date mismatch');
    }
    double? numeric(dynamic value) {
      if (value == null) {
        return null;
      }
      if (value is! num || !value.isFinite) {
        throw const FormatException('Weather number unavailable');
      }
      return value.toDouble();
    }

    final rows = raw['hours'];
    if (rows is! List || rows.length != 9) {
      throw const FormatException('Weather hours unavailable');
    }
    final hours = <WeatherForecastHour>[];
    for (var i = 0; i < 9; i++) {
      final row = rows[i];
      if (row is! Map || row['hour'] != i * 3) {
        throw const FormatException('Weather hour mismatch');
      }
      final chance = numeric(row['precipitation_probability_percent']);
      if (chance != null && (chance < 0 || chance > 100)) {
        throw const FormatException('Weather chance unavailable');
      }
      final condition = weatherCondition(row['condition']);
      hours.add(
        WeatherForecastHour(
          hour: i * 3,
          summary: condition.label,
          icon: condition.icon,
          temperatureCelsius: numeric(row['temperature_celsius']),
          rainProbability: chance?.round(),
        ),
      );
    }
    final summaryHour = raw['summary_hour'];
    final summaryTemperature = numeric(raw['summary_temperature_celsius']);
    final kind = raw['summary_kind'];
    if (kind != 'current' && kind != 'forecast_hour' && kind != 'unavailable') {
      throw const FormatException('Weather summary unavailable');
    }
    if (kind == 'forecast_hour' &&
        (summaryHour is! int ||
            summaryHour < 0 ||
            summaryHour > 21 ||
            summaryHour % 3 != 0 ||
            hours[summaryHour ~/ 3].temperatureCelsius != summaryTemperature)) {
      throw const FormatException('Weather summary mismatch');
    }
    if (expectedOffset > 0 &&
        (kind == 'current' ||
            raw['current_temperature_celsius'] != null ||
            raw['condition'] != null)) {
      throw const FormatException(
        'Future weather cannot contain current conditions',
      );
    }
    final checked = DateTime.tryParse(raw['checked_at']?.toString() ?? '');
    if (checked == null) {
      throw const FormatException('Weather timestamp unavailable');
    }
    DateTime? rainAt, rainReference;
    int? rainHour, rainMinute;
    final rain = raw['rain_approach'];
    if (rain != null) {
      DateTime? utc(dynamic value) => value is String && value.endsWith('Z')
          ? DateTime.tryParse(value)
          : null;
      if (rain is! Map ||
          expectedOffset != 0 ||
          rain['source'] != raw['source'] ||
          !['OpenWeather', 'Apple Weather'].contains(rain['source'])) {
        throw const FormatException('Precipitation forecast unavailable');
      }
      rainAt = utc(rain['forecast_at']);
      rainReference = utc(rain['reference_at']);
      final amount = numeric(rain['precipitation_mm_per_hour']);
      if (rainAt == null ||
          rainReference == null ||
          amount == null ||
          amount <= 0 ||
          rainAt.isBefore(checked) ||
          rainAt.isAfter(checked.add(const Duration(minutes: 60))) ||
          rainReference.isBefore(
            checked.subtract(const Duration(minutes: 15)),
          ) ||
          rainReference.isAfter(checked.add(const Duration(minutes: 1))) ||
          rain['local_hour'] is! int ||
          rain['local_minute'] is! int ||
          rain['local_hour'] < 0 ||
          rain['local_hour'] > 23 ||
          rain['local_minute'] < 0 ||
          rain['local_minute'] > 59) {
        throw const FormatException(
          'Precipitation forecast timestamp unavailable',
        );
      }
      rainHour = rain['local_hour'] as int;
      rainMinute = rain['local_minute'] as int;
    }
    // Unknown source conditions stay unavailable; provider codes are not UI text.
    return WeatherGatewayResult(
      baseDate: base,
      dayOffset: expectedOffset,
      timeZone: raw['time_zone'] as String,
      regionKind: raw['region_kind'] as String,
      attribution: attribution,
      radarUri: radarUri,
      snapshot: WeatherForecastSnapshot(
        locationLabel: SkoLanguageController.tr(switch (raw['region_kind']) {
          'company' => '会社周辺',
          'home' => '自宅周辺',
          'site' => '現場周辺',
          _ => '地域未設定',
        }),
        updatedAt: checked.toLocal(),
        forecastDate: forecast,
        sourceLabel: raw['source'] as String,
        hours: hours,
        radarSupported: radarUri != null,
        rainForecastAt: rainAt,
        rainReferenceAt: rainReference,
        rainLocalHour: rainHour,
        rainLocalMinute: rainMinute,
        forecastSummaryHour: kind == 'forecast_hour'
            ? summaryHour as int
            : null,
        forecastSummaryTemperatureCelsius: kind == 'forecast_hour'
            ? summaryTemperature
            : null,
        forecastSummary: kind == 'forecast_hour'
            ? weatherCondition(raw['summary_condition']).label
            : null,
        currentSummary: raw['condition'] == null
            ? null
            : weatherCondition(raw['condition']).label,
        currentTemperatureCelsius: numeric(raw['current_temperature_celsius']),
      ),
    );
  }
}

class WeatherForecastGateway {
  const WeatherForecastGateway(this.client);
  final SupabaseClient client;
  Future<WeatherGatewayResult> fetchDay(int offset) async {
    if (offset < 0 || offset > 2 || client.auth.currentUser == null) {
      throw StateError('Weather request unavailable');
    }
    final actor = client.auth.currentUser!.id;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      throw StateError("Native weather location unavailable");
    }
    final prepared = await client.functions.invoke(
      "fetch-weather-forecast",
      body: {"day_offset": offset, "prepare_location": true},
    );
    if (client.auth.currentUser?.id != actor ||
        prepared.status != 200 ||
        prepared.data is! Map) {
      throw StateError("Weather location unavailable");
    }
    final region = prepared.data as Map;
    final address = region["address"], token = region["region_token"];
    if (address is! String ||
        address.trim().isEmpty ||
        token is! String ||
        !RegExp(r"^[a-f0-9]{64}$").hasMatch(token)) {
      throw StateError("Weather location unavailable");
    }
    final native = await const MethodChannel("sko.capture_metadata")
        .invokeMapMethod<String, dynamic>("weatherGeocode", {
          "address": address,
        })
        .timeout(const Duration(seconds: 20));
    if (client.auth.currentUser?.id != actor || native == null) {
      throw StateError("Weather location unavailable");
    }
    final response = await client.functions.invoke(
      "fetch-weather-forecast",
      body: {
        "day_offset": offset,
        "native_location": native,
        "region_token": token,
      },
    );
    if (client.auth.currentUser?.id != actor || response.status != 200) {
      throw StateError('Weather response unavailable');
    }
    return WeatherGatewayResult.parse(response.data, offset);
  }
}

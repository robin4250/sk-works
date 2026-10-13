import 'package:flutter/foundation.dart';

import 'weather_forecast_card.dart';
import 'weather_forecast_policy.dart';

class WeatherForecastSnapshot {
  const WeatherForecastSnapshot({
    required this.locationLabel,
    required this.updatedAt,
    required this.forecastDate,
    required this.sourceLabel,
    this.hours = const [],
    this.currentSummary,
    this.currentTemperatureCelsius,
    this.rainApproachMessage,
    this.rainForecastAt,
    this.rainReferenceAt,
    this.rainLocalHour,
    this.rainLocalMinute,
    this.radarSupported = false,
    this.forecastSummaryTemperatureCelsius,
    this.forecastSummaryHour,
    this.forecastSummary,
  });
  final String locationLabel;
  final DateTime updatedAt;
  final DateTime forecastDate;
  final String sourceLabel;
  final List<WeatherForecastHour> hours;
  final String? currentSummary;
  final double? currentTemperatureCelsius;
  final String? rainApproachMessage;
  final DateTime? rainForecastAt;
  final DateTime? rainReferenceAt;
  final int? rainLocalHour;
  final int? rainLocalMinute;
  final bool radarSupported;
  final double? forecastSummaryTemperatureCelsius;
  final int? forecastSummaryHour;
  final String? forecastSummary;
}

/// Server adapter boundary. Clients do not own API keys or choose a provider.
typedef WeatherForecastFetcher =
    Future<WeatherForecastSnapshot> Function(
      WeatherAddressSelection address,
      DateTime forecastDate,
    );

class WeatherForecastController extends ChangeNotifier {
  WeatherForecastController({required this.fetch});
  final WeatherForecastFetcher fetch;
  WeatherForecastSnapshot? snapshot;
  bool loading = false;
  bool failed = false;
  WeatherAddressSelection address = const WeatherAddressSelection(
    WeatherAddressKind.unavailable,
    null,
  );
  DateTime? selectedDate;
  int _generation = 0;
  bool _disposed = false;

  Future<void> refresh(WeatherAddressSelection next, {DateTime? date}) async {
    if (_disposed) {
      return;
    }
    final requested = date ?? DateTime.now();
    final day = DateTime(requested.year, requested.month, requested.day);
    final generation = ++_generation;
    if (address.address != next.address ||
        address.kind != next.kind ||
        selectedDate != day) {
      snapshot = null;
    }
    address = next;
    selectedDate = day;
    failed = false;
    loading = next.address != null;
    notifyListeners();
    if (!loading) {
      return;
    }
    try {
      final result = await fetch(next, day);
      if (DateTime(
            result.forecastDate.year,
            result.forecastDate.month,
            result.forecastDate.day,
          ) !=
          day) {
        throw const FormatException('Forecast day mismatch');
      }
      if (_disposed || generation != _generation) {
        return;
      }
      snapshot = result;
    } catch (_) {
      if (_disposed || generation != _generation) {
        return;
      }
      failed = true;
    }
    if (_disposed || generation != _generation) {
      return;
    }
    loading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}

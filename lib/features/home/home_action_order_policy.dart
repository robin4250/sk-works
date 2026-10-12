/// Inserts new special cards once, while retaining every saved relative order.
List<String> normalizeHomeActionOrder(
  List<String> saved,
  List<String> available,
) {
  final result = <String>[
    for (final key in saved)
      if (available.contains(key)) key,
    for (final key in available)
      if (!saved.contains(key) &&
          key != 'weather_forecast' &&
          key != 'home_attention')
        key,
  ];
  if (available.contains('weather_forecast') &&
      !result.contains('weather_forecast')) {
    final today = result.indexOf('attendance_today');
    result.insert(today < 0 ? 0 : today + 1, 'weather_forecast');
  }
  if (available.contains('home_attention') &&
      !result.contains('home_attention')) {
    final weather = result.indexOf('weather_forecast');
    final today = result.indexOf('attendance_today');
    result.insert(
      weather >= 0
          ? weather + 1
          : today >= 0
          ? today + 1
          : 0,
      'home_attention',
    );
  }
  return result.toSet().toList();
}

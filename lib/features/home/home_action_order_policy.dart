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
          key != 'traffic_guidance' &&
          key != 'home_attention')
        key,
  ];
  if (available.contains('weather_forecast') &&
      !result.contains('weather_forecast')) {
    final today = result.indexOf('attendance_today');
    result.insert(today < 0 ? 0 : today + 1, 'weather_forecast');
  }
  if (available.contains('traffic_guidance') &&
      !result.contains('traffic_guidance')) {
    final weather = result.indexOf('weather_forecast');
    final today = result.indexOf('attendance_today');
    result.insert(weather >= 0 ? weather + 1 : today >= 0 ? today + 1 : 0, 'traffic_guidance');
  }
  if (available.contains('home_attention') &&
      !result.contains('home_attention')) {
    final traffic = result.indexOf('traffic_guidance');
    final weather = result.indexOf('weather_forecast');
    final today = result.indexOf('attendance_today');
    result.insert(
      traffic >= 0
          ? traffic + 1
          : weather >= 0
          ? weather + 1
          : today >= 0
          ? today + 1
          : 0,
      'home_attention',
    );
  }
  return result.toSet().toList();
}

/// Reorders menu entries without dropping or moving a special non-menu slot.
List<String> reorderHomeMenuActions(
  List<String> saved,
  List<String> menuOrder,
  int oldIndex,
  int newIndex,
) {
  final full = normalizeHomeActionOrder(saved, [
    ...menuOrder,
    'home_attention',
  ]);
  final ordered = full.where(menuOrder.contains).toList();
  if (oldIndex < 0 ||
      oldIndex >= ordered.length ||
      newIndex < 0 ||
      newIndex > ordered.length) {
    return full;
  }
  if (newIndex > oldIndex) {
    newIndex--;
  }
  final moved = ordered.removeAt(oldIndex);
  ordered.insert(newIndex, moved);
  var index = 0;
  return [
    for (final key in full) menuOrder.contains(key) ? ordered[index++] : key,
  ];
}

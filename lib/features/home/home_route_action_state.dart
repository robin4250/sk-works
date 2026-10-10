enum HomeRouteActionState { unavailable, arrive, move }

/// Only a complete server visit contract can activate the next route action.
HomeRouteActionState homeRouteActionState(
  Map<String, dynamic> workspace,
  String sourceId,
) {
  if (workspace['source_clock_in_id'] != sourceId ||
      workspace['visit_contract_version'] != 1 ||
      workspace['enabled'] != true ||
      workspace['is_open'] != true ||
      DateTime.tryParse(workspace['work_date']?.toString() ?? '') == null) {
    return HomeRouteActionState.unavailable;
  }
  final stops = workspace['stops'];
  final visits = workspace['visits'];
  if (stops is! List || stops.isEmpty || visits is! List) {
    return HomeRouteActionState.unavailable;
  }
  final stopIds = <String>{};
  for (final stop in stops) {
    if (stop is! Map ||
        stop['id'] is! String ||
        !stopIds.add(stop['id'] as String)) {
      return HomeRouteActionState.unavailable;
    }
  }
  var openCount = 0;
  final startIds = <String>{};
  for (final visit in visits) {
    if (visit is! Map ||
        visit['start_capture_id'] is! String ||
        !startIds.add(visit['start_capture_id'] as String) ||
        !stopIds.contains(visit['route_stop_id']) ||
        visit['work_date'] != workspace['work_date'] ||
        !visit.containsKey('end_capture_id') ||
        !visit.containsKey('ended_at')) {
      return HomeRouteActionState.unavailable;
    }
    final started = DateTime.tryParse(visit['started_at']?.toString() ?? '');
    final ended = DateTime.tryParse(visit['ended_at']?.toString() ?? '');
    if (started == null ||
        ((visit['end_capture_id'] == null) != (visit['ended_at'] == null)) ||
        (visit['end_capture_id'] != null &&
            (visit['end_capture_id'] is! String ||
                ended == null ||
                ended.isBefore(started)))) {
      return HomeRouteActionState.unavailable;
    }
    if (visit['end_capture_id'] == null) openCount++;
  }
  if (openCount > 1) return HomeRouteActionState.unavailable;
  return openCount == 1
      ? HomeRouteActionState.move
      : HomeRouteActionState.arrive;
}

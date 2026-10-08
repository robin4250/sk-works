class VehicleReportSnapshot {
  const VehicleReportSnapshot({required this.workerId, required this.sourceId,
    required this.vehicleId, required this.vehicleName, required this.hasEvent,
    this.eventId, this.previousKm, this.currentKm, this.distanceKm});
  final String workerId;
  final String sourceId;
  final String vehicleId;
  final String vehicleName;
  final bool hasEvent;
  final String? eventId;
  final double? previousKm;
  final double? currentKm;
  final double? distanceKm;
}

List<VehicleReportSnapshot> parseVehicleReportContext(Object? value, String workDate) {
  if (value is! List) {
    throw StateError('車両の勤務記録を確認できません');
  }
  final workers = <String>{};
  final sources = <String>{};
  final result = <VehicleReportSnapshot>[];
  double? number(Object? raw) {
    final parsed = raw is num ? raw.toDouble() : double.tryParse(raw?.toString() ?? '');
    return parsed != null && parsed.isFinite && parsed >= 0 ? parsed : null;
  }
  for (final row in value) {
    if (row is! Map || row['has_claim'] is! bool || row['has_event'] is! bool) {
      throw StateError('車両の勤務記録が不明です');
    }
    if (row['has_claim'] != true) {
      if (row['has_event'] == true) {
        throw StateError('車両利用記録のないメーター証跡です');
      }
      continue;
    }
    final worker = row['worker_id']?.toString() ?? '';
    final source = row['source_clock_in_id']?.toString() ?? '';
    final vehicle = row['vehicle_id']?.toString() ?? '';
    final hasEvent = row['has_event'] == true;
    final event = row['event_id']?.toString();
    final previous = number(row['previous_km']);
    final current = number(row['current_km']);
    final distance = number(row['distance_km']);
    if (worker.isEmpty || source.isEmpty || vehicle.isEmpty || !workers.add(worker) ||
        !sources.add(source) || row['work_date'] != workDate ||
        (hasEvent && (event == null || event.isEmpty || previous == null || current == null || distance == null))) {
      throw StateError('車両の対象勤務・メーター記録が一致しません');
    }
    result.add(VehicleReportSnapshot(workerId: worker, sourceId: source, vehicleId: vehicle,
      vehicleName: row['vehicle_name']?.toString() ?? '', hasEvent: hasEvent,
      eventId: event, previousKm: previous, currentKm: current, distanceKm: distance));
  }
  return List.unmodifiable(result);
}

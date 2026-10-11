/// Pure decisions only. Database transactions must enforce these rules too.
class VehicleUsagePolicy {
  const VehicleUsagePolicy._();

  static bool canStart({required String workerId, String? activeDriverId}) =>
      workerId.isNotEmpty && activeDriverId == null;

  static bool canRecordMeter({
    required String workerId,
    required String driverId,
  }) => workerId.isNotEmpty && workerId == driverId;

  /// The previous value is an immutable session/report snapshot, never a
  /// subsequently edited vehicle registration value.
  static VehicleDistanceSnapshot distance({
    required double previousKm,
    required double currentKm,
    double? manualDistanceKm,
  }) {
    _nonNegativeFinite(previousKm, 'previousKm');
    _nonNegativeFinite(currentKm, 'currentKm');
    if (manualDistanceKm != null) {
      _nonNegativeFinite(manualDistanceKm, 'manualDistanceKm');
    }
    final decreased = currentKm < previousKm;
    if (!decreased && manualDistanceKm != null) {
      throw ArgumentError('Manual distance is for a decreased meter only');
    }
    return VehicleDistanceSnapshot(
      previousKm: previousKm,
      currentKm: currentKm,
      distanceKm: decreased ? manualDistanceKm : currentKm - previousKm,
      requiresManualDistance: decreased && manualDistanceKm == null,
      notifyBaselineChange: decreased,
    );
  }

  /// Emit one event per crossed interval. The caller persists a UNIQUE key.
  /// [epochId] is replaced on a baseline reset; old report re-saves must reuse
  /// their committed result and must not call this against a fresh baseline.
  static List<VehicleMaintenanceCrossing> maintenanceCrossings({
    required String vehicleId,
    required String ruleId,
    required String epochId,
    required double originKm,
    required double previousKm,
    required double currentKm,
    required double intervalKm,
  }) {
    if ([vehicleId, ruleId, epochId].any((value) => value.isEmpty)) {
      throw ArgumentError('Stable vehicle, rule and epoch IDs are required');
    }
    _nonNegativeFinite(originKm, 'originKm');
    _nonNegativeFinite(previousKm, 'previousKm');
    _nonNegativeFinite(currentKm, 'currentKm');
    _nonNegativeFinite(intervalKm, 'intervalKm');
    if (intervalKm == 0) throw ArgumentError.value(intervalKm, 'intervalKm');
    if (currentKm < previousKm) return const [];
    if (previousKm < originKm) {
      throw ArgumentError('Previous reading precedes maintenance origin');
    }
    final first = ((previousKm - originKm) / intervalKm).floor() + 1;
    final last = ((currentKm - originKm) / intervalKm).floor();
    return List.unmodifiable([
      for (var ordinal = first; ordinal <= last; ordinal++)
        VehicleMaintenanceCrossing(
          vehicleId: vehicleId,
          ruleId: ruleId,
          epochId: epochId,
          ordinal: ordinal,
          thresholdKm: originKm + ordinal * intervalKm,
        ),
    ]);
  }

  static void _nonNegativeFinite(double value, String name) {
    if (!value.isFinite || value < 0) throw ArgumentError.value(value, name);
  }
}

class VehicleDistanceSnapshot {
  const VehicleDistanceSnapshot({
    required this.previousKm,
    required this.currentKm,
    required this.distanceKm,
    required this.requiresManualDistance,
    required this.notifyBaselineChange,
  });

  final double previousKm;
  final double currentKm;
  final double? distanceKm;
  final bool requiresManualDistance;
  final bool notifyBaselineChange;

  double get nextBaselineKm => currentKm;
}

class VehicleMaintenanceCrossing {
  const VehicleMaintenanceCrossing({
    required this.vehicleId,
    required this.ruleId,
    required this.epochId,
    required this.ordinal,
    required this.thresholdKm,
  });

  final String vehicleId;
  final String ruleId;
  final String epochId;
  final int ordinal;
  final double thresholdKm;

  /// Length prefixes prevent ambiguous keys even with separators inside IDs.
  String get eventKey => [vehicleId, ruleId, epochId, '$ordinal']
      .map((value) => '${value.length}:$value')
      .join();
}

class MasterFeatureAvailability {
  const MasterFeatureAvailability({
    required this.vehicleManagement,
    required this.routeAssignment,
    this.trafficNearestStation = false,
    this.trafficTrainTransfer = false,
    this.trafficBusStop = false,
  });

  final bool vehicleManagement;
  final bool routeAssignment;
  final bool trafficNearestStation;
  final bool trafficTrainTransfer;
  final bool trafficBusStop;

  static const unavailable = MasterFeatureAvailability(
    vehicleManagement: false,
    routeAssignment: false,
  );

  bool permitsClockIn({String? vehicleId, String? routeId}) =>
      (vehicleId == null || vehicleId.trim().isEmpty || vehicleManagement) &&
      (routeId == null || routeId.trim().isEmpty || routeAssignment);

  factory MasterFeatureAvailability.fromJson(Map<String, dynamic> json) {
    return MasterFeatureAvailability(
      vehicleManagement: json['vehicle_management'] == true,
      routeAssignment: json['route_assignment'] == true,
      trafficNearestStation: json['traffic_nearest_station'] == true,
      trafficTrainTransfer: json['traffic_train_transfer'] == true,
      trafficBusStop: json['traffic_bus_stop'] == true,
    );
  }
}

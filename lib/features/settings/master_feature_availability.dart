class MasterFeatureAvailability {
  const MasterFeatureAvailability({
    required this.vehicleManagement,
    required this.routeAssignment,
  });

  final bool vehicleManagement;
  final bool routeAssignment;

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
    );
  }
}

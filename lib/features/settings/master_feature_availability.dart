class MasterFeatureAvailability {
  const MasterFeatureAvailability({
    required this.vehicleManagement,
    required this.routeAssignment,
    this.trafficNearestStation = false,
    this.trafficTrainTransfer = false,
    this.trafficBusStop = false,
    this.companySealImageTools = false,
    this.companySealImageToolsSupported = false,
    this.qrAttendance = false,
    this.qrAttendanceSupported = false,
  });

  final bool vehicleManagement;
  final bool routeAssignment;
  final bool trafficNearestStation;
  final bool trafficTrainTransfer;
  final bool trafficBusStop;
  final bool companySealImageTools;
  final bool companySealImageToolsSupported;

  // One server flag governs both QR punches and their reader registration.
  // This contract does not establish production rollout or permission to act.
  final bool qrAttendance;
  final bool qrAttendanceSupported;
  bool get qrDeviceRegistration => qrAttendance;

  static const unavailable = MasterFeatureAvailability(
    vehicleManagement: false,
    routeAssignment: false,
  );

  bool permitsClockIn({String? vehicleId, String? routeId}) =>
      (vehicleId == null || vehicleId.trim().isEmpty || vehicleManagement) &&
      (routeId == null || routeId.trim().isEmpty || routeAssignment);

  factory MasterFeatureAvailability.fromJson(Map<String, dynamic> json) {
    final qrSupported = json['qr_attendance_contract_version'] is int &&
        json['qr_attendance_contract_version'] == 1 &&
        json['qr_attendance'] is bool;
    return MasterFeatureAvailability(
      qrAttendanceSupported: qrSupported,
      qrAttendance: qrSupported && json['qr_attendance'] == true,
      vehicleManagement: json['vehicle_management'] == true,
      routeAssignment: json['route_assignment'] == true,
      trafficNearestStation: json['traffic_nearest_station'] == true,
      trafficTrainTransfer: json['traffic_train_transfer'] == true,
      trafficBusStop: json['traffic_bus_stop'] == true,
      companySealImageTools: json['company_seal_image_tools'] == true,
      companySealImageToolsSupported: json['company_seal_image_tools'] is bool,
    );
  }
}


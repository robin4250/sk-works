class MasterFeatureAvailability {
  const MasterFeatureAvailability({
    required this.vehicleManagement,
    required this.routeAssignment,
    this.trafficNearestStation = false,
    this.trafficTrainTransfer = false,
    this.trafficBusStop = false,
    this.companySealImageTools = false,
    this.companySealImageToolsSupported = false,
    this.lifecycleFlags = const <String, bool>{},
  });

  /// New global lifecycle features fail closed when not deployed.
  final Map<String, bool> lifecycleFlags;
  static const lifecycleFeatures = <String, String>{
    'affiliation_switch': '所属切り替え',
    'sko_id_linking': 'SKO ID紐づけ',
    'personal_pdf_vault': '書類保管倉庫',
    'partner_auto_link': '協力会社自動連携',
    'company_lifecycle': '旧会社データ休止・再開',
  };
  bool lifecycleSupported(String key) => lifecycleFlags.containsKey(key);
  bool lifecycleEnabled(String key) => lifecycleFlags[key] == true;

  final bool vehicleManagement;
  final bool routeAssignment;
  final bool trafficNearestStation;
  final bool trafficTrainTransfer;
  final bool trafficBusStop;
  final bool companySealImageTools;
  final bool companySealImageToolsSupported;

  static const unavailable = MasterFeatureAvailability(
    vehicleManagement: false,
    routeAssignment: false,
  );

  bool permitsClockIn({String? vehicleId, String? routeId}) =>
      (vehicleId == null || vehicleId.trim().isEmpty || vehicleManagement) &&
      (routeId == null || routeId.trim().isEmpty || routeAssignment);

  factory MasterFeatureAvailability.fromJson(Map<String, dynamic> json) {
    return MasterFeatureAvailability(
      lifecycleFlags: Map<String, bool>.unmodifiable({
        for (final key in lifecycleFeatures.keys)
          if (json[key] is bool) key: json[key] == true,
      }),
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



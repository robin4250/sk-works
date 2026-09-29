class RouteAssignment {
  const RouteAssignment({
    required this.id,
    required this.companyId,
    required this.serviceDate,
    required this.routeName,
    this.vehicleId,
    this.siteId,
    this.driverUserId,
    this.notes,
    this.isActive = true,
  });

  final String id;
  final String companyId;
  final DateTime serviceDate;
  final String routeName;
  final String? vehicleId;
  final String? siteId;
  final String? driverUserId;
  final String? notes;
  final bool isActive;
}

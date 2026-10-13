class Vehicle {
  const Vehicle({
    required this.id,
    required this.companyId,
    required this.displayName,
    this.registrationNumber,
    this.vehicleType,
    this.capacity,
    this.notes,
    this.isActive = true,
  });

  final String id;
  final String companyId;
  final String displayName;
  final String? registrationNumber;
  final String? vehicleType;
  final int? capacity;
  final String? notes;
  final bool isActive;
}

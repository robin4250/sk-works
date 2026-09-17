class QualificationMaster {
  const QualificationMaster({
    required this.id,
    required this.name,
    this.issuer,
    this.requiresExpiry = false,
  });

  final String id;
  final String name;
  final String? issuer;
  final bool requiresExpiry;
}

class WorkerQualification {
  const WorkerQualification({
    required this.workerId,
    required this.qualificationId,
    this.certificateNumber,
    this.issueDate,
    this.expiryDate,
    this.notes,
  });

  final String workerId;
  final String qualificationId;
  final String? certificateNumber;
  final DateTime? issueDate;
  final DateTime? expiryDate;
  final String? notes;

  bool isExpiredOn(DateTime date) {
    final expiry = expiryDate;
    if (expiry == null) return false;
    final target = DateTime(date.year, date.month, date.day);
    final end = DateTime(expiry.year, expiry.month, expiry.day);
    return end.isBefore(target);
  }

  bool expiresWithin(DateTime date, Duration window) {
    final expiry = expiryDate;
    if (expiry == null) return false;
    final target = DateTime(date.year, date.month, date.day);
    final end = DateTime(expiry.year, expiry.month, expiry.day);
    if (end.isBefore(target)) return false;
    return !end.isAfter(target.add(window));
  }
}

class QualificationCatalog {
  const QualificationCatalog(this.items);

  final List<QualificationMaster> items;

  QualificationMaster? findById(String id) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  List<QualificationMaster> search(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return List.unmodifiable(items);
    return items
        .where(
          (item) =>
              item.name.toLowerCase().contains(needle) ||
              (item.issuer?.toLowerCase().contains(needle) ?? false),
        )
        .toList(growable: false);
  }
}

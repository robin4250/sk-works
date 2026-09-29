enum CompanyConnectionStatus {
  pending,
  accepted,
  rejected,
  disabled,
}

class CompanyConnection {
  const CompanyConnection({
    required this.id,
    required this.companyAId,
    required this.companyBId,
    required this.status,
  });

  final String id;
  final String companyAId;
  final String companyBId;
  final CompanyConnectionStatus status;

  bool containsCompany(String companyId) =>
      companyAId == companyId || companyBId == companyId;

  String? otherCompanyId(String companyId) {
    if (companyAId == companyId) return companyBId;
    if (companyBId == companyId) return companyAId;
    return null;
  }

  bool get isActive => status == CompanyConnectionStatus.accepted;
}

class CompanyTransferTargetPolicy {
  const CompanyTransferTargetPolicy._();

  static bool canSend({
    required String currentCompanyId,
    required String targetCompanyId,
    required Iterable<CompanyConnection> connections,
  }) {
    if (currentCompanyId.isEmpty ||
        targetCompanyId.isEmpty ||
        currentCompanyId == targetCompanyId) {
      return false;
    }

    return connections.any(
      (connection) =>
          connection.isActive &&
          connection.containsCompany(currentCompanyId) &&
          connection.otherCompanyId(currentCompanyId) == targetCompanyId,
    );
  }
}

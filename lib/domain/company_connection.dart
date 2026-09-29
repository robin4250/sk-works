enum CompanyConnectionStatus {
  pending,
  accepted,
  rejected,
  disabled,
}

class CompanyConnection {
  const CompanyConnection({
    required this.id,
    required this.parentCompanyId,
    required this.childCompanyId,
    required this.status,
  });

  final String id;
  final String parentCompanyId;
  final String childCompanyId;
  final CompanyConnectionStatus status;

  bool get isActive => status == CompanyConnectionStatus.accepted;

  bool allowsUpstreamTransfer({
    required String sourceCompanyId,
    required String targetCompanyId,
  }) =>
      isActive &&
      childCompanyId == sourceCompanyId &&
      parentCompanyId == targetCompanyId;
}

class CompanyTransferTargetPolicy {
  const CompanyTransferTargetPolicy._();

  static bool canSendUpstream({
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
      (connection) => connection.allowsUpstreamTransfer(
        sourceCompanyId: currentCompanyId,
        targetCompanyId: targetCompanyId,
      ),
    );
  }
}

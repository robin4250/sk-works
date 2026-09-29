enum TransferPayloadKind {
  personnelBundle,
  qualificationsOnly,
  documentsOnly,
}

class CompanyDataTransfer {
  const CompanyDataTransfer({
    required this.id,
    required this.sourceCompanyId,
    required this.currentCompanyId,
    required this.targetCompanyId,
    required this.workerIds,
    required this.kind,
    this.originCompanyId,
    this.forwardedFromTransferId,
  });

  final String id;
  final String sourceCompanyId;
  final String currentCompanyId;
  final String targetCompanyId;
  final List<String> workerIds;
  final TransferPayloadKind kind;

  /// Preserved across forwarding so upper-tier companies can see provenance.
  final String? originCompanyId;
  final String? forwardedFromTransferId;

  bool get includesPersonnel =>
      kind == TransferPayloadKind.personnelBundle;

  bool get includesQualifications =>
      kind == TransferPayloadKind.personnelBundle ||
      kind == TransferPayloadKind.qualificationsOnly;

  bool get includesDocuments =>
      kind == TransferPayloadKind.personnelBundle ||
      kind == TransferPayloadKind.documentsOnly;
}

class TransferConfirmation {
  const TransferConfirmation({
    required this.targetCompanyId,
    required this.workerIds,
    required this.kind,
    required this.confirmed,
  });

  final String targetCompanyId;
  final List<String> workerIds;
  final TransferPayloadKind kind;
  final bool confirmed;

  bool get canSend =>
      confirmed && targetCompanyId.isNotEmpty && workerIds.isNotEmpty;
}

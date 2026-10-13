enum SettlementDocumentKind { invoice, paymentStatement, finalSettlement }

class IntercompanySettlementKey {
  const IntercompanySettlementKey({required this.upperCompanyId, required this.lowerCompanyId, required this.year, required this.month});
  final String upperCompanyId;
  final String lowerCompanyId;
  final int year;
  final int month;
  String get stableKey => '$upperCompanyId:$lowerCompanyId:${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';
}

class SettlementDocumentRef {
  const SettlementDocumentRef({required this.settlementKey, required this.kind, required this.documentId});
  final IntercompanySettlementKey settlementKey;
  final SettlementDocumentKind kind;
  final String documentId;
}

class SettlementFolderPolicy {
  const SettlementFolderPolicy._();
  static String upperCompanyFolder({required String lowerCompanyName, required int year, required int month}) =>
      '協力会社/$lowerCompanyName/請求・精算/$year/${month.toString().padLeft(2, '0')}';
  static String lowerCompanyFolder({required String upperCompanyName, required int year, required int month}) =>
      '取引先/$upperCompanyName/請求・精算/$year/${month.toString().padLeft(2, '0')}';
}

import 'company_seal_snapshot.dart';

/// Draft output uses current settings without changing the saved document.
/// Every other state, including unknown states, keeps its original snapshot.
bool invoiceUsesCurrentSeal(Map<String, dynamic> row) =>
    row['status'] == 'draft' &&
    row.containsKey('finalized_at') &&
    row.containsKey('approval_finalized_at') &&
    row['finalized_at'] == null &&
    row['approval_finalized_at'] == null &&
    row['invoice_seal_frozen'] == false;

CompanySealSnapshot invoiceDocumentSeal({
  required Map<String, dynamic> document,
  required Object? saved,
  required Map<String, dynamic>? currentCompany,
  required String companyId,
}) {
  if (!invoiceUsesCurrentSeal(document)) {
    return CompanySealSnapshot.fromJson(saved);
  }
  if (currentCompany == null || currentCompany['id'] != companyId) {
    throw StateError('請求書の現在の角印設定を確認できません。再読み込みしてください。');
  }
  return CompanySealSnapshot.forPreview(currentCompany);
}

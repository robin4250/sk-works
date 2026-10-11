import 'company_seal_snapshot.dart';

/// Draft output uses current settings without changing the saved document.
/// Every other state, including unknown states, keeps its original snapshot.
CompanySealSnapshot invoiceDocumentSeal({
  required Object? status,
  required Object? saved,
  required Map<String, dynamic>? currentCompany,
  required String companyId,
}) {
  if (status != 'draft') return CompanySealSnapshot.fromJson(saved);
  if (currentCompany == null || currentCompany['id'] != companyId) {
    throw StateError('請求書の現在の角印設定を確認できません。再読み込みしてください。');
  }
  return CompanySealSnapshot.forPreview(currentCompany);
}

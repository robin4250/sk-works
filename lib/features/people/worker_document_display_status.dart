/// Presentation of the saved document evidence, separate from exemptions.
/// A submission row alone is not evidence that a required attachment exists.
class WorkerDocumentDisplayStatus {
  const WorkerDocumentDisplayStatus(this.label, this.complete);
  final String label;
  final bool complete;
}

WorkerDocumentDisplayStatus workerDocumentDisplayStatus(
  Map<String, dynamic> requirement,
  Map<String, dynamic>? row, {
  String? effectiveStatus,
}) {
  final status = effectiveStatus ?? row?['status']?.toString();
  if (row == null || status == 'not_submitted' || status == 'missing') {
    return const WorkerDocumentDisplayStatus('未登録', false);
  }
  if (status == 'expired') {
    return const WorkerDocumentDisplayStatus('期限切れ', false);
  }
  if (status != 'submitted' && status != 'verified') {
    return const WorkerDocumentDisplayStatus('状態を確認', false);
  }
  // Bank information has its own private-record completion check. Do not
  // require an identity-document upload in place of that separate evidence.
  final bank = requirement['name'] == '銀行口座情報';
  if (requirement['is_required'] == true &&
      !bank &&
      (row['attachment_path']?.toString().trim().isEmpty ?? true)) {
    return const WorkerDocumentDisplayStatus('添付待ち', false);
  }
  if (requirement['expiry_required'] == true &&
      (row['expires_at']?.toString().trim().isEmpty ?? true)) {
    return const WorkerDocumentDisplayStatus('提出済み・期限未入力', false);
  }
  return const WorkerDocumentDisplayStatus('登録済み', true);
}

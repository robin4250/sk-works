/// Keeps legacy/local invoices separate from saved workspace-backed documents.
class InvoiceAcceptanceWorkspaceGuard {
  const InvoiceAcceptanceWorkspaceGuard._();

  static bool shouldLoad({
    required String invoiceId,
    required String? sourceRevision,
    required bool hasExplicitSelection,
    required bool repositoryAvailable,
  }) {
    // Includes an explicitly supplied null for a historical missing appendix.
    if (hasExplicitSelection) return false;
    // Local/synthetic calculations have no persisted source contract.
    if (invoiceId.isEmpty || sourceRevision == null) return false;
    if (!repositoryAvailable) {
      throw StateError(
        '注文請書を確認できません。ログイン状態を確認し、請求書を再読み込みしてください。',
      );
    }
    return true;
  }
}

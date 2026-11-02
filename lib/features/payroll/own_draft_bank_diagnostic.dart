/// Finite metadata only: never attach bank data, identity, token, request/response,
/// an original exception or stack trace to a diagnostic.
enum OwnDraftBankReadStage { session, admission, statement, request, response }
enum OwnDraftBankReadIssue {
  sessionUnavailable, authenticationEvent, authenticationStream,
  logoutQuarantine, admissionRejected, statementRejected,
  rpcDenied, rpcUnavailable, rpcRejected, timeout, transport,
  invalidResponse, basisUnavailable,
}
class OwnDraftBankDiagnostic {
  const OwnDraftBankDiagnostic(this.stage, this.issue);
  final OwnDraftBankReadStage stage;
  final OwnDraftBankReadIssue issue;
  String get safeCode => 'own_bank_${stage.name}_${issue.name}';
  Map<String,String> get safeMetadata => {'stage':stage.name,'issue':issue.name};
}
class OwnDraftBankReadFailure extends StateError {
  OwnDraftBankReadFailure(this.diagnostic) : super(diagnostic.safeCode);
  final OwnDraftBankDiagnostic diagnostic;
  @override String toString() => 'Own bank confirmation unavailable (${diagnostic.safeCode})';
}

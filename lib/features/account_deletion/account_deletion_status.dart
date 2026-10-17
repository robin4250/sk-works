enum AccountDeletionState { noRequest, requested, processing, failed, completed, unknown }

class AccountDeletionStatus {
  const AccountDeletionStatus(this.state, {this.createdAt, this.dueAt});
  final AccountDeletionState state;
  final DateTime? createdAt;
  final DateTime? dueAt;

  factory AccountDeletionStatus.fromResponse(dynamic raw) {
    if (raw is! Map || !raw.containsKey('request') || raw.containsKey('error')) {
      return const AccountDeletionStatus(AccountDeletionState.unknown);
    }
    final request = raw['request'];
    if (request == null) { return const AccountDeletionStatus(AccountDeletionState.noRequest); }
    if (request is! Map || request['request_id'] is! String ||
        (request['request_id'] as String).trim().isEmpty) {
      return const AccountDeletionStatus(AccountDeletionState.unknown);
    }
    final state = switch (request['status']) {
      'requested' => AccountDeletionState.requested,
      'processing' => AccountDeletionState.processing,
      'failed' => AccountDeletionState.failed,
      'completed' => AccountDeletionState.completed,
      _ => AccountDeletionState.unknown,
    };
    DateTime? date(dynamic value) => value is String ? DateTime.tryParse(value) : null;
    return AccountDeletionStatus(state, createdAt: date(request['created_at']), dueAt: date(request['due_at']));
  }
}

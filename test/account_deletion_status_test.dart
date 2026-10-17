import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/account_deletion/account_deletion_status.dart';
import 'package:sk_works/features/account_deletion/account_deletion_repository.dart';

void main() {
  test('explicit null is no request, malformed and errors are unknown', () {
    expect(AccountDeletionStatus.fromResponse({'request': null}).state, AccountDeletionState.noRequest);
    for (final raw in [null, {}, {'error': 'unavailable'}, {'request': {}}, {'request': null, 'error': 'unavailable'}]) {
      expect(AccountDeletionStatus.fromResponse(raw).state, AccountDeletionState.unknown);
    }
  });
  test('requested and processing never become completed', () {
    for (final entry in {'requested': AccountDeletionState.requested, 'processing': AccountDeletionState.processing,
      'failed': AccountDeletionState.failed, 'completed': AccountDeletionState.completed, 'new_status': AccountDeletionState.unknown}.entries) {
      final result = AccountDeletionStatus.fromResponse({'request': {'request_id': 'fixture', 'status': entry.key, 'due_at': '2000-01-01T00:00:00Z'}});
      expect(result.state, entry.value);
    }
  });
  test('invalid dates do not fabricate dates or completion', () {
    final result = AccountDeletionStatus.fromResponse({'request': {'request_id': 'fixture', 'status': 'requested', 'due_at': 'invalid'}});
    expect(result.state, AccountDeletionState.requested);
    expect(result.dueAt, isNull);
    expect(AccountDeletionRepository.intakeEnabled, isFalse);
  });
}

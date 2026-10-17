import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/supabase_backend.dart';
import 'account_deletion_status.dart';

/// Read-only subject status. No intake, Auth mutation or service credentials.
class AccountDeletionRepository {
  AccountDeletionRepository._(this._client);
  final SupabaseClient _client;
  static const intakeEnabled = false;

  static AccountDeletionRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) { return null; }
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) { return null; }
    return AccountDeletionRepository._(client);
  }

  Future<AccountDeletionStatus> load() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) { throw StateError('login_required'); }
    final response = await _client.functions.invoke('account-deletion', method: HttpMethod.get);
    if (_client.auth.currentUser?.id != userId) { throw StateError('session_changed'); }
    if (response.status != 200) { throw StateError('status_unavailable'); }
    final status = AccountDeletionStatus.fromResponse(response.data);
    if (status.state == AccountDeletionState.unknown) { throw StateError('status_unavailable'); }
    return status;
  }
}

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class HomeMembershipRepository {
  HomeMembershipRepository._(this._client);

  final SupabaseClient _client;

  static HomeMembershipRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return HomeMembershipRepository._(client);
  }

  Future<String> loadRole() async {
    final user = _client.auth.currentUser;
    if (user == null) return 'viewer';

    final rows = await _client
        .from('company_members')
        .select('role')
        .eq('user_id', user.id)
        .limit(1);

    if (rows.isEmpty) return 'viewer';
    return rows.first['role']?.toString() ?? 'viewer';
  }
}

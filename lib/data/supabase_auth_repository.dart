import 'package:supabase_flutter/supabase_flutter.dart';

import 'contracts.dart';

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<AppUser?> currentUser() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    return _loadMembership(user.id, user.email);
  }

  @override
  Future<AppUser> signIn({required String email, required String password}) async {
    final response = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    final user = response.user;
    if (user == null) {
      throw StateError('Sign-in succeeded without a user record.');
    }
    return _loadMembership(user.id, user.email ?? email);
  }

  @override
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  Future<AppUser> _loadMembership(String userId, String? fallbackName) async {
    final rows = await _client
        .from('company_members')
        .select('company_id, role')
        .eq('user_id', userId)
        .limit(1);

    if (rows.isEmpty) {
      throw StateError('No SK WORKS company membership exists for this account.');
    }

    final row = rows.first;
    final roleName = row['role'] as String? ?? 'viewer';

    return AppUser(
      id: userId,
      companyId: row['company_id'] as String,
      displayName: fallbackName ?? 'SK WORKS User',
      role: UserRole.values.firstWhere(
        (role) => role.name == roleName,
        orElse: () => UserRole.viewer,
      ),
    );
  }
}

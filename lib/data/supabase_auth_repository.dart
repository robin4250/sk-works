import 'package:supabase_flutter/supabase_flutter.dart';

import 'contracts.dart';
import '../features/auth/app_auth_mutation_gateway.dart';
import '../features/auth/apple_session_navigation_binding.dart';

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
  Future<AppUser> signIn({required String email, required String password, String? captchaToken}) async {
    final user = await AppAuthMutationGateway.forClient(_client).signInWithPassword(
      email: email,
      password: password,
      captchaToken: captchaToken,
    );
    if (user == null) {
      throw StateError('Sign-in succeeded without a user record.');
    }
    return _loadMembership(user.id, user.email ?? email);
  }

  @override
  Future<void> signOut() async {
    await AppAuthMutationGateway.forClient(_client).signOut();
  }

  Future<AppUser> _loadMembership(String userId, String? fallbackName) async {
    final session = _client.auth.currentSession;
    final binding = AppleSessionNavigationBinding.fromSession(session);
    if (session == null || session.user.id != userId || binding == null) {
      throw StateError('Authentication changed before membership read.');
    }
    final rows = await _client
        .from('company_members')
        .select('company_id, role')
        .eq('user_id', userId)
        .limit(1)
        .setHeader('Authorization', 'Bearer ${session.accessToken}');
    if (AppleSessionNavigationBinding.fromSession(_client.auth.currentSession) != binding) {
      throw StateError('Authentication changed during membership read.');
    }

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

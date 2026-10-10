import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

/// Verifies the fixed current actor without replacing the application's session.
/// This client has no persistent storage, session listener or token refresh.
class SecondaryPasswordPrimaryVerifier {
  SecondaryPasswordPrimaryVerifier({
    required this.currentUser,
    GoTrueClient Function()? createClient,
  }) : _createClient = createClient ?? _temporaryClient;

  final User? Function() currentUser;
  final GoTrueClient Function() _createClient;

  static GoTrueClient _temporaryClient() => GoTrueClient(
    url: '${SupabaseBackendConfig.url}/auth/v1',
    headers: {
      'apikey': SupabaseBackendConfig.publishableKey,
      'Authorization': 'Bearer ${SupabaseBackendConfig.publishableKey}',
    },
    autoRefreshToken: false,
  );

  Future<bool> verify(String password) async {
    final user = currentUser();
    if (user == null) return false;
    final phone = user.phone;
    final email = user.email;
    if ((phone == null || phone.isEmpty) && (email == null || email.isEmpty)) {
      return false;
    }
    final client = _createClient();
    AuthResponse response;
    try {
      response = await client.signInWithPassword(
        phone: phone != null && phone.isNotEmpty ? phone : null,
        email: phone != null && phone.isNotEmpty ? null : email,
        password: password,
      );
    } finally {
      try {
        // Revoke only the temporary verification session, never all sessions.
        await client.signOut(scope: SignOutScope.local);
      } finally {
        client.dispose();
      }
    }
    return response.user?.id == user.id && currentUser()?.id == user.id;
  }
}

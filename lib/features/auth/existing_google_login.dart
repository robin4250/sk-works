import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

/// Uses the existing provider and allowlisted native callback. This does not
/// create an application company, grant a role, link identities, or set passwords.
class ExistingGoogleLogin {
  ExistingGoogleLogin(this.client);

  final SupabaseClient client;
  static const nativeRedirect = 'com.skworks.sko://login-callback/';

  static ExistingGoogleLogin? maybeCreate() => SupabaseBackend.isInitialized
      ? ExistingGoogleLogin(SupabaseBackend.client)
      : null;

  Session? get currentSession => client.auth.currentSession;
  Stream<AuthState> get changes => client.auth.onAuthStateChange;

  Future<bool> launch() {
    if (kIsWeb) throw UnsupportedError('Native Google callback is required');
    return client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: nativeRedirect,
        queryParams: const {'prompt': 'select_account'},
      );
  }

  Future<bool> hasExistingMembership(Session session) async {
    if (currentSession?.user.id != session.user.id ||
        currentSession?.accessToken != session.accessToken) return false;
    final rows = await client
        .from('company_members')
        .select('company_id')
        .eq('user_id', session.user.id)
        .limit(1)
        .setHeader('Authorization', 'Bearer ${session.accessToken}');
    return rows.isNotEmpty &&
        currentSession?.user.id == session.user.id &&
        currentSession?.accessToken == session.accessToken;
  }
}

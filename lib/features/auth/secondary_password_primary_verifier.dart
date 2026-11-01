import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import 'secondary_reset_session_guard.dart';

/// Verifies the fixed current actor without replacing the application's session.
/// The temporary client has no persistent storage or token refresh. The original
/// session is observed until verification and temporary-session cleanup finish.
class SecondaryPasswordPrimaryVerifier {
  SecondaryPasswordPrimaryVerifier({
    required this.currentUser,
    required this.currentSession,
    required this.authChanges,
    GoTrueClient Function()? createClient,
  }) : _createClient = createClient ?? _temporaryClient;

  final User? Function() currentUser;
  final Session? Function() currentSession;
  final Stream<AuthState> authChanges;
  final GoTrueClient Function() _createClient;

  static GoTrueClient _temporaryClient() => GoTrueClient(
    url: '${SupabaseBackendConfig.url}/auth/v1',
    headers: {
      'apikey': SupabaseBackendConfig.publishableKey,
      'Authorization': 'Bearer ${SupabaseBackendConfig.publishableKey}',
    },
    autoRefreshToken: false,
  );

  Future<bool> verify(String password, {String? captchaToken}) async {
    final user = currentUser();
    if (user == null) return false;
    final phone = user.phone;
    final email = user.email;
    if ((phone == null || phone.isEmpty) && (email == null || email.isEmpty)) {
      return false;
    }
    SecondaryResetSessionGuard guard;
    try {
      guard = SecondaryResetSessionGuard(currentSession: currentSession,
        changes: authChanges);
    } on StateError { return false; }
    if (currentSession()?.user.id != user.id) {
      await guard.close();
      return false;
    }
    try {
      final originalKey = SecondaryResetSessionGuard.identityOf(currentSession());
      final client = _createClient();
      AuthResponse response;
      bool distinctTemporarySession = false;
      try {
        response = await client.signInWithPassword(
          phone: phone != null && phone.isNotEmpty ? phone : null,
          email: phone != null && phone.isNotEmpty ? null : email,
          password: password,
          captchaToken: captchaToken,
        );
        final temporaryKey = SecondaryResetSessionGuard.identityOf(response.session);
        distinctTemporarySession = temporaryKey != null && temporaryKey != originalKey;
      } finally {
        try {
          // Never revoke the original/global session if Auth unexpectedly reuses it.
          final temporaryKey = SecondaryResetSessionGuard.identityOf(client.currentSession);
          if (temporaryKey != null && temporaryKey != originalKey &&
              temporaryKey != SecondaryResetSessionGuard.identityOf(currentSession())) {
            await client.signOut(scope: SignOutScope.local);
          }
        } finally { client.dispose(); }
      }
      try { await guard.checkAfterQueuedEvents(); }
      on StateError { return false; }
      return distinctTemporarySession && response.user?.id == user.id && currentUser()?.id == user.id;
    } finally { await guard.close(); }
  }
}


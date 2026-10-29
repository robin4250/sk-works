import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/supabase_backend.dart';
import 'app_auth_mutation_gateway.dart';

/// Uses the existing provider and allowlisted native callback. This does not
/// create an application company, grant a role, link identities, or set passwords.
class ExistingGoogleLogin {
  ExistingGoogleLogin(this.client);

  final SupabaseClient client;
  static const nativeRedirect = 'com.skworks.sko://login-callback/';
  static bool get supportedPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static ExistingGoogleLogin? maybeCreate() => SupabaseBackend.isInitialized
      ? ExistingGoogleLogin(SupabaseBackend.client)
      : null;

  Session? get currentSession => client.auth.currentSession;
  Stream<AuthState> get changes => client.auth.onAuthStateChange;

  Future<bool> launch() async {
    if (!supportedPlatform) {
      throw UnsupportedError('Verified iOS Google callback is required');
    }
    final owner = AppAuthMutationGateway.forClient(client);
    final epoch = await owner.externalFlowAdmission();
    if (epoch == null || !owner.isExternalFlowCurrent(epoch)) throw StateError('Authentication operation already in progress.');
    final response = await client.auth.getOAuthSignInUrl(
        provider: OAuthProvider.google,
        redirectTo: nativeRedirect,
        queryParams: const {'prompt': 'select_account'},
      );
    // Pinned SDK iOS launch semantics: platformDefault and _self. Recheck after
    // PKCE storage awaits, immediately before the native handoff.
    if (!owner.isExternalFlowCurrent(epoch)) throw StateError('Authentication changed before browser launch.');
    final launched = await launchUrl(Uri.parse(response.url),
        mode: LaunchMode.platformDefault, webOnlyWindowName: '_self');
    if (!owner.isExternalFlowCurrent(epoch)) throw StateError('Authentication changed during browser launch.');
    return launched;
  }

  Future<bool> hasExistingMembership(Session session) async {
    final owner = AppAuthMutationGateway.forClient(client);
    final epoch = await owner.externalFlowAdmission();
    bool current() => epoch != null && owner.isExternalFlowCurrent(epoch) &&
        currentSession?.user.id == session.user.id &&
        currentSession?.accessToken == session.accessToken;
    if (!current()) return false;
    final rows = await client
        .from('company_members')
        .select('company_id')
        .eq('user_id', session.user.id)
        .limit(1)
        .setHeader('Authorization', 'Bearer ${session.accessToken}');
    // The client-lifetime gateway observer stays subscribed through return,
    // avoiding a per-read cancellation await that could lose SDK A→B→A history.
    await Future<void>.value();
    return rows.isNotEmpty && current();
  }
}

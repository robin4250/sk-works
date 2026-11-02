import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/supabase_backend.dart';

/// Additional client restriction; server authorization remains mandatory.
/// Canonical UID from the scoped, single-enabled-registry read-only capture.
/// Compiled into source so release/CI environment omission cannot silently deny the owner.
/// This identifier is not a secret and never replaces server authorization.
class MasterOwnerAccess {
  static const ownerId = '9b6e82ca-d4f3-41d6-baff-5642566557a0';
  static bool allows(Session? session) => ownerId.isNotEmpty &&
      session != null && !session.isExpired && session.user.id == ownerId;
  static bool get current => SupabaseBackend.isInitialized &&
      allows(SupabaseBackend.client.auth.currentSession);
  static Future<bool> check(SupabaseClient client, {String? accessToken}) async {
    final captured = client.auth.currentSession;
    if (!allows(captured) || (accessToken != null && accessToken != captured!.accessToken)) { return false; }
    final token = captured!.accessToken;
    final raw = await client.rpc('current_master_admin_status')
        .setHeader('Authorization', 'Bearer $token');
    final now = client.auth.currentSession;
    return allows(now) && identical(now, captured) && now!.accessToken == token &&
        raw is Map && raw['is_master_admin'] == true;
  }
}

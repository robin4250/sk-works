import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/supabase_backend.dart';
import 'own_published_shift_gateway.dart';

/// Preparation only: server rollout and real-device checks are not complete.
/// This cannot be enabled by a client preference or an untrusted server claim.
const ownShiftEntryReleased = false;

class OwnShiftContext {
  const OwnShiftContext(this.companyId, this.siteNames, this.gateway);
  final String companyId;
  final Map<String, String> siteNames;
  final OwnPublishedShiftGateway gateway;
}

/// Read-only adapter. No worker identifier is accepted from the route: the RPC
/// determines the caller's own worker and enforces publication and rollout.
class OwnPublishedShiftRepository {
  OwnPublishedShiftRepository(this.client) {
    _subscription = client.auth.onAuthStateChange.listen((_) => _generation++);
  }
  final SupabaseClient client;
  late final StreamSubscription<AuthState> _subscription;
  int _generation = 0;
  bool _disposed = false;

  static OwnPublishedShiftRepository? maybeCreate() =>
      SupabaseBackend.isInitialized && SupabaseBackend.client.auth.currentSession != null
          ? OwnPublishedShiftRepository(SupabaseBackend.client) : null;

  void dispose() {
    _disposed = true;
    _generation++;
    unawaited(_subscription.cancel());
  }

  Future<OwnShiftContext> loadContext() async {
    final session = client.auth.currentSession;
    if (session == null || session.user.isAnonymous) throw StateError('ログインを確認してください。');
    final actor = session.user.id, token = session.accessToken, generation = _generation;
    void check() {
      final current = client.auth.currentSession;
      if (_disposed || _generation != generation || current == null ||
          current.user.id != actor || current.accessToken != token) {
        throw StateError('ログイン状態が変わりました。画面を開き直してください。');
      }
    }
    check();
    final memberships = await client.from('company_members').select('company_id')
        .eq('user_id', actor).limit(2);
    check();
    // Do not guess a company when an account has multiple memberships.
    if (memberships.length != 1 || memberships.single['company_id'] is! String ||
        (memberships.single['company_id'] as String).trim().isEmpty) {
      throw StateError('所属会社を一つに確認できません。');
    }
    final company = memberships.single['company_id'] as String;
    final rows = await client.from('sites').select('id,name').eq('company_id', company);
    check();
    final names = <String, String>{};
    for (final row in rows) {
      if (row['id'] is String && row['name'] is String) {
        names[row['id'] as String] = row['name'] as String;
      }
    }
    final gateway = OwnPublishedShiftGateway((name, params) async {
      check();
      if (name != 'list_own_published_shifts' || params['p_company'] != company) {
        throw StateError('本人のシフトを確認できません。');
      }
      final result = await client.rpc(name, params: params);
      check();
      return result;
    });
    return OwnShiftContext(company, Map.unmodifiable(names), gateway);
  }
}

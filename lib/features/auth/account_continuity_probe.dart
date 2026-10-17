import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Read-only preservation checks for a future authenticated Apple link.
/// This does not launch OAuth, link identities, create users or authorize linking.
class AccountContinuityProbe {
  AccountContinuityProbe(this.client);
  final SupabaseClient client;

  bool _matches(String actor, String token) =>
      client.auth.currentUser?.id == actor &&
      client.auth.currentSession?.accessToken == token;

  Future<ContinuitySnapshot> capture() async {
    final session = client.auth.currentSession;
    if (session == null) throw const ContinuityRejected();
    final actor = session.user.id, token = session.accessToken;
    final user = (await client.auth.getUser(token)).user;
    if (user == null || user.id != actor || !_matches(actor, token)) {
      throw const ContinuityRejected();
    }
    final identities = _identities(user);
    if (identities.values.contains('apple')) {
      throw const ContinuityRejected();
    }
    final memberships = await _memberships(actor, token);
    if (!_matches(actor, token)) throw const ContinuityRejected();
    return ContinuitySnapshot._(
        actor, token, identities, memberships);
  }

  Future<void> verifyAdded(ContinuitySnapshot before) async {
    if (!_matches(before._actor, before._token)) {
      throw const ContinuityRejected();
    }
    final user = (await client.auth.getUser(before._token)).user;
    if (user == null || user.id != before._actor ||
        !_matches(before._actor, before._token)) {
      throw const ContinuityRejected();
    }
    final after = _identities(user);
    if (!after.values.contains('apple') ||
        before._identities.entries.any((e) => after[e.key] != e.value)) {
      throw const ContinuityRejected();
    }
    final memberships = await _memberships(before._actor, before._token);
    if (!_matches(before._actor, before._token) ||
        memberships != before._memberships) {
      throw const ContinuityRejected();
    }
  }

  Map<String, String> _identities(User user) {
    final identities = <String, String>{};
    for (final identity in user.identities ?? <UserIdentity>[]) {
      final value = identity.toJson();
      final id = value['identity_id'], provider = value['provider'];
      if (id is! String || id.isEmpty || provider is! String ||
          provider.isEmpty || identities.containsKey(id)) {
        throw const ContinuityRejected();
      }
      identities[id] = provider;
    }
    if (identities.isEmpty) throw const ContinuityRejected();
    return Map.unmodifiable(identities);
  }

  Future<String> _memberships(String actor, String token) async {
    final rows = await client.from('company_members')
        .select('company_id,role').eq('user_id', actor)
        .setHeader('Authorization', 'Bearer $token');
    if (!_matches(actor, token)) throw const ContinuityRejected();
    final memberships = <String>[];
    for (final row in rows) {
      if (row['company_id'] is! String || row['role'] is! String) {
        throw const ContinuityRejected();
      }
      memberships.add(jsonEncode([row['company_id'], row['role']]));
    }
    if (memberships.isEmpty) throw const ContinuityRejected();
    memberships.sort();
    return jsonEncode(memberships);
  }
}

class ContinuitySnapshot {
  ContinuitySnapshot._(
      this._actor, this._token, this._identities, this._memberships);
  final String _actor, _token, _memberships;
  final Map<String, String> _identities;
}

class ContinuityRejected implements Exception {
  const ContinuityRejected();
  @override String toString() => 'Apple identity preservation could not be verified';
}

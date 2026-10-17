import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Read-only preservation checks for a future authenticated Apple link.
/// This does not launch OAuth, link identities, create users or authorize linking.
class ExistingAppleIdentityLink {
  ExistingAppleIdentityLink(this.client);
  final SupabaseClient client;

  bool _matches(String actor, String token) =>
      client.auth.currentUser?.id == actor &&
      client.auth.currentSession?.accessToken == token;

  Future<AppleIdentityPreservationSnapshot> capture() async {
    final session = client.auth.currentSession;
    if (session == null) throw const AppleIdentityPreservationRejected();
    final actor = session.user.id, token = session.accessToken;
    final user = (await client.auth.getUser(token)).user;
    if (user == null || user.id != actor || !_matches(actor, token)) {
      throw const AppleIdentityPreservationRejected();
    }
    final identities = _identities(user);
    if (identities.values.contains('apple')) {
      throw const AppleIdentityPreservationRejected();
    }
    final memberships = await _memberships(actor, token);
    if (!_matches(actor, token)) throw const AppleIdentityPreservationRejected();
    return AppleIdentityPreservationSnapshot._(
        actor, token, identities, memberships);
  }

  Future<void> verifyAdded(AppleIdentityPreservationSnapshot before) async {
    if (!_matches(before._actor, before._token)) {
      throw const AppleIdentityPreservationRejected();
    }
    final user = (await client.auth.getUser(before._token)).user;
    if (user == null || user.id != before._actor ||
        !_matches(before._actor, before._token)) {
      throw const AppleIdentityPreservationRejected();
    }
    final after = _identities(user);
    if (!after.values.contains('apple') ||
        before._identities.entries.any((e) => after[e.key] != e.value)) {
      throw const AppleIdentityPreservationRejected();
    }
    final memberships = await _memberships(before._actor, before._token);
    if (!_matches(before._actor, before._token) ||
        memberships != before._memberships) {
      throw const AppleIdentityPreservationRejected();
    }
  }

  Map<String, String> _identities(User user) {
    final identities = <String, String>{};
    for (final identity in user.identities ?? <UserIdentity>[]) {
      final value = identity.toJson();
      final id = value['identity_id'], provider = value['provider'];
      if (id is! String || id.isEmpty || provider is! String ||
          provider.isEmpty || identities.containsKey(id)) {
        throw const AppleIdentityPreservationRejected();
      }
      identities[id] = provider;
    }
    if (identities.isEmpty) throw const AppleIdentityPreservationRejected();
    return Map.unmodifiable(identities);
  }

  Future<String> _memberships(String actor, String token) async {
    final rows = await client.from('company_members')
        .select('company_id,role').eq('user_id', actor)
        .setHeader('Authorization', 'Bearer $token');
    if (!_matches(actor, token)) throw const AppleIdentityPreservationRejected();
    final memberships = <String>[];
    for (final row in rows) {
      if (row['company_id'] is! String || row['role'] is! String) {
        throw const AppleIdentityPreservationRejected();
      }
      memberships.add(jsonEncode([row['company_id'], row['role']]));
    }
    if (memberships.isEmpty) throw const AppleIdentityPreservationRejected();
    memberships.sort();
    return jsonEncode(memberships);
  }
}

class AppleIdentityPreservationSnapshot {
  AppleIdentityPreservationSnapshot._(
      this._actor, this._token, this._identities, this._memberships);
  final String _actor, _token, _memberships;
  final Map<String, String> _identities;
}

class AppleIdentityPreservationRejected implements Exception {
  const AppleIdentityPreservationRejected();
  @override String toString() => 'Apple identity preservation could not be verified';
}

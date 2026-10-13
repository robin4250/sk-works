import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import 'security_incident.dart';

class SecurityIncidentRepository {
  SecurityIncidentRepository(this._client);
  final SupabaseClient _client;
  static SecurityIncidentRepository? maybeCreate() =>
      SupabaseBackend.isInitialized &&
          SupabaseBackend.client.auth.currentUser != null
      ? SecurityIncidentRepository(SupabaseBackend.client)
      : null;
  Future<List<SecurityIncident>> load() async {
    final actor = _client.auth.currentUser?.id;
    if (actor == null) throw StateError('Security records unavailable');
    final response = await _client.rpc('master_security_incidents');
    if (_client.auth.currentUser?.id != actor)
      throw StateError('Security records unavailable');
    return SecurityIncident.parseResponse(response);
  }
}

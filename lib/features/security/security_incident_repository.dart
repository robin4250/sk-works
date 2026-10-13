import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import 'security_incident.dart';
import 'security_incident_report.dart';

class SecurityIncidentRepository {
  SecurityIncidentRepository(this._client);
  final SupabaseClient _client;
  String? get currentActor => _client.auth.currentUser?.id;
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
    if (utf8.encode(jsonEncode(response)).length > 512 * 1024)
      throw StateError('Security records unavailable');
    return SecurityIncident.parseResponse(response);
  }

  Future<void> authorizeExport(
    SecurityIncidentReportData report,
    String? actor,
  ) async {
    if (actor == null || currentActor != actor)
      throw StateError('Security records unavailable');
    final records = await load();
    final matches = records.where((record) => record.id == report.record.id);
    if (currentActor != actor ||
        matches.length != 1 ||
        SecurityIncidentReportData(
              matches.single,
              generatedAt: report.generatedAt,
            ).digest !=
            report.digest) {
      throw StateError('Security records unavailable');
    }
  }
}

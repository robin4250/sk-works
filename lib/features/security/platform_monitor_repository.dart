import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import '../auth/operation_reauthentication_repository.dart';

class PlatformMonitorUnavailable implements Exception {}

class PlatformMonitorSnapshot {
  PlatformMonitorSnapshot._(this.events, this.windows);
  final List<Map<String, dynamic>> events;
  final List<Map<String, dynamic>> windows;

  static PlatformMonitorSnapshot parse(Object? response) {
    if (response is! Map ||
        response.length != 7 ||
        response['version'] != 1 ||
        response['source_provenance'] != 'supabase_platform_logs' ||
        response['scope'] != 'platform_operator' ||
        response['retention_days'] != 7 ||
        response['coverage'] != 'bounded_queries_not_continuous_monitoring' ||
        response['events'] is! List ||
        response['windows'] is! List ||
        utf8.encode(jsonEncode(response)).length > 128 * 1024) {
      throw const FormatException('Platform monitoring unavailable');
    }
    List<Map<String, dynamic>> rows(String key, Set<String> keys) {
      final values = response[key] as List;
      if (values.length > 100) {
        throw const FormatException('Platform monitoring unavailable');
      }
      return List.unmodifiable(values.map((row) {
        if (row is! Map ||
            row.length != keys.length ||
            !row.keys.every(keys.contains) ||
            !const {'edge_logs', 'postgres_logs', 'auth_audit_logs'}.contains(row['source']) ||
            row['key_epoch'] is! int ||
            (row['key_epoch'] as int) < 1) {
          throw const FormatException('Platform monitoring unavailable');
        }
        if (key == 'events') {
          if (!const {'unknown', 'http_success', 'unauthenticated', 'forbidden', 'rate_limited', 'server_error', 'permission_denied'}.contains(row['result']) ||
              row['event_key'] is! String ||
              !RegExp(r'^[0-9a-f]{64}$').hasMatch(row['event_key'] as String) ||
              row['source_key'] != null || row['source_tracking'] != 'unavailable' ||
              row['occurred_at'] is! String ||
              DateTime.tryParse(row['occurred_at'] as String) == null ||
              (row['target_key'] != null && (row['target_key'] is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(row['target_key'] as String)))) {
            throw const FormatException('Platform monitoring unavailable');
          }
        } else if (!const {'bounded_query', 'capacity_limited'}.contains(row['coverage']) ||
            row['event_count'] is! int || (row['event_count'] as int) < 0 || (row['event_count'] as int) > 1000 ||
            row['window_from'] is! String || DateTime.tryParse(row['window_from'] as String) == null ||
            row['window_to'] is! String || DateTime.tryParse(row['window_to'] as String) == null) {
          throw const FormatException('Platform monitoring unavailable');
        }
        return Map<String, dynamic>.unmodifiable(Map<String, dynamic>.from(row));
      }));
    }
    return PlatformMonitorSnapshot._(
      rows('events', {'source', 'key_epoch', 'event_key', 'occurred_at', 'result', 'target_key', 'source_key', 'source_tracking'}),
      rows('windows', {'source', 'window_from', 'window_to', 'key_epoch', 'coverage', 'event_count'}),
    );
  }
}

class PlatformMonitorRepository {
  PlatformMonitorRepository(this.client, this.reauthentication);
  final SupabaseClient client;
  final OperationReauthenticationRepository reauthentication;
  String? get currentActor => client.auth.currentUser?.id;

  static PlatformMonitorRepository? maybeCreate() {
    final reauthentication = OperationReauthenticationRepository.maybeCreate();
    if (!SupabaseBackend.isInitialized || reauthentication == null) return null;
    return PlatformMonitorRepository(SupabaseBackend.client, reauthentication);
  }

  Future<bool> available() async {
    final actor = currentActor;
    if (actor == null) throw StateError('Platform monitoring unavailable');
    final flags = await reauthentication.capabilities();
    if (currentActor != actor) throw StateError('Platform monitoring unavailable');
    return flags['master_security'] == true;
  }

  Future<PlatformMonitorSnapshot> load(String password) async {
    final actor = currentActor;
    if (actor == null || !await available()) throw PlatformMonitorUnavailable();
    final proof = await reauthentication.requestProof(
      password: password,
      operation: 'master.security_incidents.read',
      target: const {'scope': 'platform'},
    );
    if (currentActor != actor) throw StateError('Platform monitoring unavailable');
    try {
      final response = await client.rpc('master_platform_security_monitor', params: {'p_proof': proof});
      if (currentActor != actor) throw StateError('Platform monitoring unavailable');
      return PlatformMonitorSnapshot.parse(response);
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST202' || error.code == '55000') throw PlatformMonitorUnavailable();
      rethrow;
    }
  }
}

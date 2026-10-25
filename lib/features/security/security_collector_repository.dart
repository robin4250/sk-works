import 'dart:async';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import '../auth/operation_reauthentication_repository.dart';

class SecurityCollectorUnavailable implements Exception {}

class SecurityCollectorSnapshot {
  SecurityCollectorSnapshot._(this.events);
  final List<Map<String, dynamic>> events;

  // DateTime.tryParse normalizes impossible dates (for example February 31).
  // Audit evidence must keep the calendar/time the server actually supplied.
  static bool _calendarDate(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null || match.end != value.length) return false;
    final year = int.parse(match[1]!);
    final month = int.parse(match[2]!);
    final day = int.parse(match[3]!);
    if (year < 1) return false;
    final date = DateTime.utc(year, month, day);
    return date.year == year && date.month == month && date.day == day;
  }

  static bool _timestamp(String value) {
    final match = RegExp(r'^(\d{4}-\d{2}-\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,6})?(Z|[+-]\d{2}:\d{2})$')
        .firstMatch(value);
    if (match == null || match.end != value.length || !_calendarDate(match[1]!) ||
        int.parse(match[2]!) > 23 || int.parse(match[3]!) > 59 ||
        int.parse(match[4]!) > 59) {
      return false;
    }
    final zone = match[5]!;
    if (zone != 'Z' && (int.parse(zone.substring(1, 3)) > 23 ||
        int.parse(zone.substring(4, 6)) > 59)) {
      return false;
    }
    return DateTime.tryParse(value) != null;
  }

  static SecurityCollectorSnapshot parse(dynamic raw) {
    const keys = {'version', 'source_provenance', 'coverage', 'attack_confirmed', 'events'};
    if (raw is! Map || raw.length != keys.length || !raw.keys.every(keys.contains) ||
        raw['version'] != 1 || raw['source_provenance'] != 'trusted_collector_observation' ||
        raw['coverage'] != 'collector_observations_only' || raw['attack_confirmed'] != false ||
        raw['events'] is! List || (raw['events'] as List).length > 100 ||
        utf8.encode(jsonEncode(raw)).length > 128 * 1024) {
      throw const FormatException('Collector response unavailable');
    }
    final rows = <Map<String, dynamic>>[];
    final seen = <String>{};
    final uuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
    const eventKeys = {'event_id','collector_id','occurred_at','received_at',
      'event_kind','generation','correlation_key','key_epoch','source_provenance'};
    for (final row in raw['events'] as List) {
      if (row is! Map || row.length != eventKeys.length || !row.keys.every(eventKeys.contains) ||
          row['event_id'] is! String || !uuid.hasMatch(row['event_id'] as String) ||
          !seen.add(row['event_id'] as String) || row['collector_id'] is! String ||
          !uuid.hasMatch(row['collector_id'] as String) || row['generation'] is! int ||
          (row['generation'] as int) < 1 || (row['generation'] as int) > 1000000 ||
          !const {'current_lure_touched','retired_lure_touched'}.contains(row['event_kind']) ||
          row['correlation_key'] is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(row['correlation_key'] as String) ||
          row['source_provenance'] != 'trusted_collector_observation' ||
          row['key_epoch'] is! String || !_calendarDate(row['key_epoch'] as String) ||
          ['occurred_at','received_at'].any((key) => row[key] is! String || !_timestamp(row[key] as String))) {
        throw const FormatException('Collector event unavailable');
      }
      rows.add(Map<String, dynamic>.unmodifiable(Map<String, dynamic>.from(row)));
    }
    return SecurityCollectorSnapshot._(List.unmodifiable(rows));
  }
}

/// Proofs are local to one call. A failure never retries a consumed proof.
class SecurityCollectorRepository {
  SecurityCollectorRepository({required this.sessionKey, required this.availableCheck,
    required this.issueProof, required this.readWithProof, required this.sessionChanges});
  final String? Function() sessionKey;
  final Future<bool> Function() availableCheck;
  final Future<String> Function(String password) issueProof;
  final Future<dynamic> Function(String proof) readWithProof;
  final Stream<String?> sessionChanges;

  static String? _key(SupabaseClient client) {
    final session = client.auth.currentSession;
    if (session == null || session.isExpired) return null;
    return _eventKey(session);
  }

  // Preserve the identity IN each event: an async callback must not replace
  // an A→B→A sequence with the already-restored current session A. Historical
  // token expiry does not change a session identity; current expiry is checked
  // separately by _key before/after work. No bearer token leaves this helper.
  static String? _eventKey(Session? session) {
    if (session == null) return null;
    try {
      final parts = session.accessToken.split('.');
      final claims = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      final sid = claims is Map ? claims['session_id'] : null;
      return sid is String && sid.isNotEmpty ? '${session.user.id}/$sid' : null;
    } catch (_) { return null; }
  }

  static SecurityCollectorRepository? maybeCreate() {
    final reauth = OperationReauthenticationRepository.maybeCreate();
    if (!SupabaseBackend.isInitialized || reauth == null) return null;
    final client = SupabaseBackend.client;
    return SecurityCollectorRepository(
      sessionKey: () => _key(client),
      sessionChanges: client.auth.onAuthStateChange.map((event) =>
        event.event == AuthChangeEvent.signedOut ? null : _eventKey(event.session)),
      availableCheck: () async {
        final master = await client.rpc('is_current_user_master_admin');
        if (master != true) return false;
        return (await reauth.capabilities())['master_security'] == true;
      },
      issueProof: (password) => reauth.requestProof(password: password,
        operation: 'master.security_collector.read', target: const {'scope':'decoy_collector'}),
      readWithProof: (proof) {
        // RPC defaults to POST: the proof is a JSON body, never a URL/query.
        return client.rpc('master_security_collector_events', params: {'p_proof':proof});
      },
    );
  }

  Future<T> _bound<T>(Future<T> Function(void Function()) work, {bool Function()? isActive}) async {
    final initial = sessionKey();
    if (initial == null) throw SecurityCollectorUnavailable();
    var revoked = false;
    final subscription = sessionChanges.listen((eventKey) {
      if (eventKey != initial || sessionKey() != initial) revoked = true;
    }, onError: (Object _) { revoked = true; });
    void check() {
      if (revoked || sessionKey() != initial || isActive?.call() == false) throw SecurityCollectorUnavailable();
    }
    try {
      check();
      final result = await work(check);
      check();
      return result;
    } finally { await subscription.cancel(); }
  }

  Future<bool> available() => _bound((check) async {
    try {
      final result = await availableCheck().timeout(const Duration(seconds: 20)); check(); return result;
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST202') return false;
      rethrow;
    }
  });

  Future<SecurityCollectorSnapshot> load(String password, {bool Function()? isActive}) => _bound((check) async {
    if (password.isEmpty || !await available()) throw SecurityCollectorUnavailable();
    check();
    final proof = await issueProof(password).timeout(const Duration(seconds: 30));
    check();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(proof)) throw SecurityCollectorUnavailable();
    try {
      final raw = await readWithProof(proof).timeout(const Duration(seconds: 20));
      check();
      return SecurityCollectorSnapshot.parse(raw);
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST202' || error.code == '55000') throw SecurityCollectorUnavailable();
      rethrow;
    }
  }, isActive: isActive);
}

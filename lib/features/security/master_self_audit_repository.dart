import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import 'master_self_operation_audit.dart';
import 'master_self_audit_snapshot.dart';
export 'master_self_audit_snapshot.dart';

class MasterSelfAuditRepository {
  MasterSelfAuditRepository(this._client);
  final SupabaseClient _client;
  String? get currentActor => _client.auth.currentUser?.id;
  static MasterSelfAuditRepository? maybeCreate() =>
      SupabaseBackend.isInitialized &&
          SupabaseBackend.client.auth.currentUser != null
      ? MasterSelfAuditRepository(SupabaseBackend.client)
      : null;

  Future<MasterSelfAuditSnapshot> load({DateTime? cutoff}) async {
    final actor = currentActor;
    if (actor == null) {
      throw StateError('Audit unavailable');
    }
    final operations = await _client.rpc(
      'master_self_operation_audit',
      params: {'p_cutoff': cutoff?.toUtc().toIso8601String()},
    );
    final operationEvents = MasterSelfOperationAuditEvent.parse(operations);
    final fixedCutoff = DateTime.parse((operations as Map)['cutoff'] as String);
    if (cutoff != null && fixedCutoff != cutoff.toUtc()) {
      throw StateError('Audit unavailable');
    }
    if (currentActor != actor) {
      throw StateError('Audit unavailable');
    }
    final authentication = await _client.rpc(
      'master_self_auth_audit',
      params: {'p_cutoff': fixedCutoff.toIso8601String()},
    );
    if (currentActor != actor ||
        utf8.encode(jsonEncode([operations, authentication])).length >
            128 * 1024) {
      throw StateError('Audit unavailable');
    }
    if (authentication is! Map ||
        authentication['cutoff'] != fixedCutoff.toIso8601String()) {
      throw StateError('Audit unavailable');
    }
    return MasterSelfAuditSnapshot(
      cutoff: fixedCutoff,
      operations: operationEvents,
      authentication: MasterSelfOperationAuditEvent.parse(
        authentication,
        auth: true,
      ),
    );
  }

  Future<void> authorizeExport(
    MasterSelfAuditSnapshot snapshot,
    String? actor,
  ) => authorizeMasterSelfAuditSnapshot(
    snapshot: snapshot,
    actor: actor,
    currentActor: () => currentActor,
    loadAtCutoff: (cutoff) => load(cutoff: cutoff),
  );
}

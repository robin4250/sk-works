import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../lib/features/security/master_self_audit_snapshot.dart';
import '../lib/features/security/master_self_operation_audit.dart';

void main() {
  final cutoff = DateTime.utc(2026, 10, 14, 1);
  MasterSelfAuditSnapshot snapshot({String action = 'login'}) =>
      MasterSelfAuditSnapshot(
        cutoff: cutoff,
        operations: const [],
        authentication: [
          MasterSelfOperationAuditEvent(action: action, at: cutoff),
        ],
      );
  test(
    'third party JSON identifies both sources, cutoff and limits with UTC/JST',
    () {
      final data = jsonDecode(snapshot().json) as Map;
      expect(data['cutoff_utc'], '2026-10-14T01:00:00.000Z');
      expect(data['cutoff_jst'], '2026-10-14T10:00:00.000+09:00');
      expect(data['scope'], 'self_master_account');
      expect((data['sources'] as List).map((s) => s['source_provenance']), [
        'server_master_operation_audit',
        'supabase_auth_database_audit',
      ]);
      expect(data['explanation_ja'], contains('全失敗や全アクセスの網羅ではありません'));
      expect(snapshot().json, isNot(contains('actor_id')));
    },
  );
  test(
    'export fixes cutoff before reauthentication adds newer events',
    () async {
      DateTime? requested;
      await authorizeMasterSelfAuditSnapshot(
        snapshot: snapshot(),
        actor: 'A',
        currentActor: () => 'A',
        loadAtCutoff: (at) async {
          requested = at;
          return snapshot();
        },
      );
      expect(requested, cutoff);
      await expectLater(
        authorizeMasterSelfAuditSnapshot(
          snapshot: snapshot(),
          actor: 'A',
          currentActor: () => 'A',
          loadAtCutoff: (_) async => snapshot(action: 'logout'),
        ),
        throwsStateError,
      );
    },
  );
  test(
    'export rejects changed actors before and during the server recheck',
    () async {
      var actor = 'B';
      var calls = 0;
      await expectLater(
        authorizeMasterSelfAuditSnapshot(
          snapshot: snapshot(),
          actor: 'A',
          currentActor: () => actor,
          loadAtCutoff: (_) async {
            calls++;
            return snapshot();
          },
        ),
        throwsStateError,
      );
      expect(calls, 0);
      actor = 'A';
      await expectLater(
        authorizeMasterSelfAuditSnapshot(
          snapshot: snapshot(),
          actor: 'A',
          currentActor: () => actor,
          loadAtCutoff: (_) async {
            actor = 'B';
            return snapshot();
          },
        ),
        throwsStateError,
      );
    },
  );
}

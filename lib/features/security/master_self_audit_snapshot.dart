import 'dart:convert';

import 'master_self_operation_audit.dart';

class MasterSelfAuditSnapshot {
  MasterSelfAuditSnapshot({
    required this.cutoff,
    required List<MasterSelfOperationAuditEvent> operations,
    required List<MasterSelfOperationAuditEvent> authentication,
  }) : operations = List.unmodifiable(operations),
       authentication = List.unmodifiable(authentication);
  final DateTime cutoff;
  final List<MasterSelfOperationAuditEvent> operations;
  final List<MasterSelfOperationAuditEvent> authentication;

  Map<String, Object> _source(
    String provenance,
    List<MasterSelfOperationAuditEvent> events,
  ) => {
    'source_provenance': provenance,
    'events': events
        .map(
          (e) => {
            'action': e.action,
            'at_utc': e.at.toUtc().toIso8601String(),
            'at_jst':
                '${e.at.toUtc().add(const Duration(hours: 9)).toIso8601String().replaceFirst('Z', '')}+09:00',
            'meaning_ja': e.label(false),
            'meaning_en': e.label(true),
          },
        )
        .toList(growable: false),
  };

  Map<String, Object> get data => {
    'format_version': 1,
    'scope': 'self_master_account',
    'cutoff_utc': cutoff.toUtc().toIso8601String(),
    'cutoff_jst':
        '${cutoff.toUtc().add(const Duration(hours: 9)).toIso8601String().replaceFirst('Z', '')}+09:00',
    'limit_per_source': 100,
    'explanation_ja': '本人にひも付いたサーバー実記録のみ。マスター操作とSupabase Authのデータベース保存分は別の記録元。不正アクセスの確定・全失敗や全アクセスの網羅ではありません。0件は安全・未発生を意味しません。本文・連絡先・IP・端末名・生IDは含みません。取得基準日時以前の各最新100件です。',
    'explanation_en': 'Only server records attributed to this master account. Master operations and Supabase Auth database audit are separate sources. These do not establish intrusion or cover all failures or requests. Zero events does not prove safety or absence. Bodies, contacts, IPs, device names and raw IDs are excluded. Latest 100 events per source at or before the fixed cutoff.',
    'sources': [
      _source('server_master_operation_audit', operations),
      _source('supabase_auth_database_audit', authentication),
    ],
  };

  String get canonical => jsonEncode(data);
  String get json => const JsonEncoder.withIndent('  ').convert(data);
}

Future<void> authorizeMasterSelfAuditSnapshot({
  required MasterSelfAuditSnapshot snapshot,
  required String? actor,
  required String? Function() currentActor,
  required Future<MasterSelfAuditSnapshot> Function(DateTime cutoff)
  loadAtCutoff,
}) async {
  if (actor == null || currentActor() != actor) {
    throw StateError('Audit unavailable');
  }
  final current = await loadAtCutoff(snapshot.cutoff);
  if (currentActor() != actor || current.canonical != snapshot.canonical) {
    throw StateError('Audit unavailable');
  }
}

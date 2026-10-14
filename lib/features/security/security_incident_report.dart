import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'security_incident.dart';

class SecurityIncidentReportData {
  SecurityIncidentReportData(this.record, {DateTime? generatedAt})
    : generatedAt = (generatedAt ?? DateTime.now()).toUtc();
  final SecurityIncident record;
  final DateTime generatedAt;
  Map<String, dynamic> get metadata => {
    'report_version': 1,
    'record_version': record.recordVersion,
    'saved_at_utc': record.savedAt.toIso8601String(),
    'first_seen_utc': record.firstSeen?.toIso8601String(),
    'last_seen_utc': record.lastSeen?.toIso8601String(),
    'source_provenance': record.provenance,
    'source_tracking': record.sourceTracking,
    'correlation_confidence': record.confidence,
    'reason_code': 'decoy_lure_touched',
    'audit': [
      for (final a in record.audit)
        {
          'action': 'imported',
          'at_utc': a.at.toIso8601String(),
          'operator': 'self_master',
          'record_version': a.recordVersion,
        },
    ],
    'generated_at_utc': generatedAt.toIso8601String(),
    'incident_id': record.id,
    'correlation_id': record.correlationId,
    'detected_at_utc': record.detectedAt.toIso8601String(),
    'window_from_utc': record.windowFrom.toIso8601String(),
    'window_to_utc': record.windowTo.toIso8601String(),
    'status': record.status,
    'collection_status': record.collectionStatus,
    'missing_before': record.missingBefore,
    'missing_after': record.missingAfter,
    'event_count': record.events.length,
    'events': [
      for (final e in record.events)
        {
          'sequence': e.sequence,
          'at_utc': e.at.toIso8601String(),
          'kind': e.kind,
          'generation': e.generation,
        },
    ],
  };
  String get digest =>
      sha256.convert(utf8.encode(jsonEncode(metadata))).toString();
  String get json => const JsonEncoder.withIndent('  ').convert({
    ...metadata,
    'metadata_sha256': digest,
    'integrity_notice': 'Digest comparison only; this is not a signature or proof of authenticity.',
  });
  List<String> lines(bool english) => [
    ...record.reportLines(english),
    '${english ? 'Report version' : '記録書式の版'}: 1 / ${record.recordVersion}',
    '${english ? 'Record type' : '記録区分'}: ${record.recordVersion > 1 ? (english ? 'Continuation' : '継続記録') : (english ? 'Initial record' : '初回記録')}',
    '${english ? 'Collected events' : '収集済み回数'}: ${record.events.length}',
    english
        ? 'Counts refer only to collected events, not an inferred lifetime total.'
        : '回数は収集済みイベント数です。未収集の累積回数は推測していません。',
    '${english ? 'First / last (UTC)' : '初回／最終 (UTC)'}: ${record.firstSeen?.toIso8601String() ?? (english ? 'Unavailable' : '未収集')} / ${record.lastSeen?.toIso8601String() ?? (english ? 'Unavailable' : '未収集')}',
    '${english ? 'Saved (UTC)' : '保管日時 (UTC)'}: ${record.savedAt.toIso8601String()}',
    '${english ? 'Generated (UTC)' : '作成日時 (UTC)'}: ${generatedAt.toIso8601String()}',
    '${english ? 'Detected (JST, UTC+09:00)' : '検知日時 (日本時間 JST・UTC+09:00)'}: ${record.detectedAt.add(const Duration(hours: 9)).toIso8601String().replaceAll('Z', '+09:00')}',
    english
        ? 'Reason: a decoy endpoint was accessed. This can include validation or mistaken access; investigation is required.'
        : '検知理由：通常の業務操作では使わないデコイ（おとりの入口）にアクセスがありました。検証や誤操作の可能性もあるため、調査が必要です。',
    english
        ? 'Source: synthetic validation fixture, not an actual production incident. Correlation is limited to supplied synthetic metadata; actor identity is not established.'
        : '取得元：合成データによる検証記録です。実際の本番インシデントではありません。関連性は提供された合成メタデータの範囲に限られ、アクセスした実人物は特定していません。',
    english
        ? 'Scope: decoy events only. This report does not establish a production database intrusion.'
        : '対象：デコイのイベントのみ。本番データベースへの侵入を示す記録ではありません。',
    english
        ? 'Response history: import audit below; operator means the authenticated importing master, not an attacker. Remediation and investigation results are not collected.'
        : '対応履歴：下記は保管操作の履歴です。「マスター本人」は取り込んだ操作者を指し、攻撃者ではありません。対処措置や調査結果は未収集で、推測して補っていません。',
    english
        ? 'Glossary: generation is a decoy configuration revision; correlation ID relates records, not a personal identifier. Missing logs indicate incomplete collection.'
        : '用語：世代はデコイ構成の改訂番号。関連IDは記録の照合用で、人物識別ではありません。前後ログ不足は収集が不完全であることを示します。',
    for (final a in record.audit)
      '${a.at.toIso8601String()} | ${english ? 'Imported by master self' : 'マスター本人が検証記録を保管'} | ${english ? 'Record version' : '記録版'} ${a.recordVersion}',
    '${english ? 'Metadata SHA-256' : '照合用メタデータ SHA-256'}: $digest',
    english
        ? 'This digest checks consistency with the JSON export. It is not a signature and alone does not guarantee authenticity.'
        : 'このハッシュは同じ記録のJSONとの整合性照合用です。電子署名ではなく、これだけで改ざん防止や真正性を保証しません。',
  ];
}

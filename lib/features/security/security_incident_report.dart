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
    '${english ? 'Report version' : '記録書式の版'}: 1',
    '${english ? 'Generated (UTC)' : '作成日時 (UTC)'}: ${generatedAt.toIso8601String()}',
    '${english ? 'Detected (JST, UTC+09:00)' : '検知日時 (日本時間 JST・UTC+09:00)'}: ${record.detectedAt.add(const Duration(hours: 9)).toIso8601String().replaceAll('Z', '+09:00')}',
    english
        ? 'Reason: a decoy endpoint was accessed. This can include validation or mistaken access; investigation is required.'
        : '検知理由：通常の業務操作では使わないデコイ（おとりの入口）にアクセスがありました。検証や誤操作の可能性もあるため、調査が必要です。',
    english
        ? 'Source: isolated decoy metadata. Correlation is based on the same correlation ID, event sequence and generation; actor identity is not established.'
        : '取得元：隔離したデコイの安全化済みメタデータ。関連ID・イベント順序・世代を照合した記録です。アクセスした実人物は特定していません。',
    english
        ? 'Scope: decoy events only. This report does not establish a production database intrusion.'
        : '対象：デコイのイベントのみ。本番データベースへの侵入を示す記録ではありません。',
    english
        ? 'Response history: not collected in this report. No action or investigation result is inferred.'
        : '対応履歴：この記録では未収集。担当者・措置・結果を推測して補っていません。',
    english
        ? 'Glossary: generation is a decoy configuration revision; correlation ID relates records, not a personal identifier. Missing logs indicate incomplete collection.'
        : '用語：世代はデコイ構成の改訂番号。関連IDは記録の照合用で、人物識別ではありません。前後ログ不足は収集が不完全であることを示します。',
    '${english ? 'Metadata SHA-256' : '照合用メタデータ SHA-256'}: $digest',
    english
        ? 'This digest checks consistency with the JSON export. It is not a signature and alone does not guarantee authenticity.'
        : 'このハッシュは同じ記録のJSONとの整合性照合用です。電子署名ではなく、これだけで改ざん防止や真正性を保証しません。',
  ];
}

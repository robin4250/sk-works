class SecurityIncident {
  const SecurityIncident({
    required this.id,
    required this.correlationId,
    required this.detectedAt,
    required this.windowFrom,
    required this.windowTo,
    required this.status,
    required this.collectionStatus,
    required this.missingBefore,
    required this.missingAfter,
    required this.events,
    required this.recordVersion,
    required this.savedAt,
    required this.firstSeen,
    required this.lastSeen,
    required this.provenance,
    required this.confidence,
    required this.sourceTracking,
    required this.audit,
  });
  final String id, correlationId, status, collectionStatus;
  final DateTime detectedAt, windowFrom, windowTo;
  final bool missingBefore, missingAfter;
  final List<SecurityIncidentEvent> events;
  final int recordVersion;
  final DateTime savedAt, firstSeen, lastSeen;
  final String provenance, confidence, sourceTracking;
  final List<SecurityIncidentAudit> audit;

  static List<SecurityIncident> parseResponse(dynamic response) {
    if (response is! Map ||
        response['version'] != 1 ||
        response['incidents'] is! List) {
      throw const FormatException('Security records unavailable');
    }
    final rows = response['incidents'] as List;
    if (rows.length > 100) {
      throw const FormatException('Security records unavailable');
    }
    return List.unmodifiable(
      rows.map((row) {
        if (row is! Map ||
            row['events'] is! List ||
            (row['events'] as List).length > 128 ||
            row['missing_before'] is! bool ||
            row['missing_after'] is! bool) {
          throw const FormatException('Security records unavailable');
        }
        final events =
            (row['events'] as List).map(SecurityIncidentEvent.parse).toList()
              ..sort((a, b) => a.sequence.compareTo(b.sequence));
        if (events.isEmpty ||
            row['event_count'] != events.length ||
            events.map((e) => e.sequence).toSet().length != events.length) {
          throw const FormatException('Security records unavailable');
        }
        final from = _date(row['window_from']), to = _date(row['window_to']);
        final first = _date(row['first_seen']), last = _date(row['last_seen']);
        final version = row['record_version'];
        if (version is! int ||
            version < 1 ||
            version > 16 ||
            row['audit'] is! List ||
            (row['audit'] as List).length > 16 ||
            last.isBefore(first)) {
          throw const FormatException('Security records unavailable');
        }
        _enum(row['reason_code'], const {'decoy_lure_touched'});
        _enum(row['timezone'], const {'UTC'});
        if (first != events.first.at ||
            last != events.last.at ||
            from.isAfter(first) ||
            to.isBefore(last) ||
            to.isBefore(from)) {
          throw const FormatException('Security records unavailable');
        }
        return SecurityIncident(
          id: _id(row['incident_id']),
          correlationId: _id(row['correlation_id']),
          detectedAt: _date(row['detected_at']),
          windowFrom: from,
          windowTo: to,
          status: _enum(row['status'], const {
            'detected',
            'confirmed',
            'dismissed',
          }),
          collectionStatus: _enum(row['collection_status'], const {
            'collecting',
            'complete',
            'partial',
          }),
          missingBefore: row['missing_before'] as bool,
          missingAfter: row['missing_after'] as bool,
          events: List.unmodifiable(events),
          recordVersion: version,
          savedAt: _date(row['saved_at']),
          firstSeen: first,
          lastSeen: last,
          provenance: _enum(row['source_provenance'], const {
            'synthetic_fixture',
          }),
          confidence: _enum(row['correlation_confidence'], const {
            'unavailable',
            'synthetic_source_only',
          }),
          sourceTracking: _enum(row['source_tracking'], const {
            'unavailable',
            'synthetic_pseudonym',
          }),
          audit: List.unmodifiable(
            (row['audit'] as List).map(SecurityIncidentAudit.parse),
          ),
        );
      }),
    );
  }

  String statusLabel(bool english) => switch (status) {
    'confirmed' => english ? 'Confirmed' : '確認済み',
    'dismissed' => english ? 'Dismissed' : '誤検知等',
    _ => english ? 'Needs investigation' : '要調査',
  };
  String collectionLabel(bool english) => switch (collectionStatus) {
    'complete' => english ? 'Complete' : '収集完了',
    'partial' => english ? 'Partial' : '一部不足',
    _ => english ? 'Collecting' : '収集中',
  };
  List<String> reportLines(bool english) => [
    english ? 'SKO Security Record — Beta' : 'SKO セキュリティ記録 ベータ版',
    '${english ? 'Record ID' : '記録ID'}: $id',
    '${english ? 'Correlation ID' : '関連ID'}: $correlationId',
    '${english ? 'Detected' : '検知日時'}: ${detectedAt.toUtc().toIso8601String()}',
    '${english ? 'Window (UTC)' : '収集期間 (UTC)'}: ${windowFrom.toUtc().toIso8601String()} — ${windowTo.toUtc().toIso8601String()}',
    '${english ? 'Investigation' : '調査区分'}: ${statusLabel(english)}',
    '${english ? 'Collection' : '収集状態'}: ${collectionLabel(english)}',
    '${english ? 'Missing before / after' : '前ログ不足／後ログ不足'}: $missingBefore / $missingAfter',
    english
        ? 'Detection alone does not confirm an attack. No message bodies, personal information or secrets are included.'
        : '検知のみで攻撃と断定しません。本文・個人情報・秘密情報は含みません。',
    for (final event in events)
      '${event.sequence} | ${event.at.toUtc().toIso8601String()} | ${event.label(english)} | ${english ? 'Generation' : '世代'} ${event.generation}',
  ];
}

class SecurityIncidentEvent {
  const SecurityIncidentEvent(
    this.sequence,
    this.at,
    this.kind,
    this.generation,
  );
  final int sequence, generation;
  final DateTime at;
  final String kind;
  static SecurityIncidentEvent parse(dynamic row) {
    if (row is! Map ||
        row['sequence'] is! int ||
        row['generation'] is! int ||
        (row['sequence'] as int) < 1 ||
        (row['generation'] as int) < 1) {
      throw const FormatException('Security records unavailable');
    }
    return SecurityIncidentEvent(
      row['sequence'] as int,
      _date(row['at']),
      _enum(row['kind'], const {
        'current_lure_touched',
        'retired_lure_touched',
      }),
      row['generation'] as int,
    );
  }

  String label(bool english) => kind == 'current_lure_touched'
      ? (english ? 'Current decoy accessed' : '現行デコイへのアクセス')
      : (english ? 'Retired decoy accessed' : '旧デコイへのアクセス');
}

String _enum(dynamic value, Set<String> values) {
  if (value is! String || !values.contains(value)) {
    throw const FormatException('Security records unavailable');
  }
  return value;
}

String _id(dynamic value) {
  if (value is! String ||
      !RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(value)) {
    throw const FormatException('Security records unavailable');
  }
  return value;
}

DateTime _date(dynamic value) {
  if (value is! String || !RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(value)) {
    throw const FormatException('Security records unavailable');
  }
  return DateTime.parse(value).toUtc();
}

class SecurityIncidentAudit {
  const SecurityIncidentAudit(this.at, this.recordVersion);
  final DateTime at;
  final int recordVersion;
  static SecurityIncidentAudit parse(dynamic row) {
    if (row is! Map ||
        row['record_version'] is! int ||
        (row['record_version'] as int) < 1 ||
        (row['record_version'] as int) > 16) {
      throw const FormatException('Security records unavailable');
    }
    _enum(row['action'], const {'imported'});
    _enum(row['operator'], const {'self_master'});
    return SecurityIncidentAudit(
      _date(row['at']),
      row['record_version'] as int,
    );
  }
}

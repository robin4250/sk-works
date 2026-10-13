import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/route_journey_capture_draft.dart';
import 'package:sk_works/features/daily_reports/daily_report_repository.dart';
import 'package:sk_works/features/daily_reports/daily_report_pdf_evidence.dart';

void main() {
  RouteJourneyCaptureDraft draft() => RouteJourneyCaptureDraft(userId: 'user', companyId: 'company',
    sourceId: 'original-start', stopId: 'actual-stop', originKind: 'company',
    preparedAt: DateTime.utc(2026, 10, 8, 14, 59),
    payload: {'capture_contract_version': 1, 'gps_capture_status': 'failed',
      'photo_capture_status': 'failed', 'captured_address': null});
  Map<String, dynamic> saved(RouteJourneyCaptureDraft d) => {'id': d.id,
    'company_id': d.companyId, 'created_by': d.userId, 'source_clock_in_id': d.sourceId,
    'route_stop_id': d.stopId, 'origin_kind': d.originKind, 'payload': d.payload,
    'work_date': '2026-10-07', 'recorded_at': '2026-10-08T15:00:00Z'};
  test('fixed identity and raw failure survive reload without invented work_date', () {
    final original = draft(); final restored = RouteJourneyCaptureDraft.restore(original.encoded);
    expect(restored.id, original.id); expect(restored.encoded, original.encoded);
    expect(restored.payload['captured_address'], isNull);
    expect(() => restored.payload['gps_capture_status'] = 'acquired', throwsUnsupportedError);
    expect(restored.payload.containsKey('work_date'), isFalse);
    final invalid = jsonDecode(original.encoded) as Map;
    (invalid['payload'] as Map)['work_date'] = '2026-10-08';
    expect(() => RouteJourneyCaptureDraft.restore(jsonEncode(invalid)), throwsStateError);
  });
  test('nested JSON recovery uses content equality and remains immutable', () {
    final d = RouteJourneyCaptureDraft(userId: 'user', companyId: 'company',
      sourceId: 'source', stopId: 'stop', originKind: 'direct',
      payload: {'capture_contract_version': 1, 'nested': {'values': [1, null, 'a']}});
    final row = saved(d);
    row['payload'] = jsonDecode(jsonEncode(d.payload));
    expect(d.matchesRow(row), isTrue);
    expect(() => (d.payload['nested'] as Map)['new'] = 1, throwsUnsupportedError);
  });
  test('new calendar day prevents new insert but permits exact recovery of original work_date', () async {
    final d = draft(); expect(d.canInsertOn(DateTime.utc(2026, 10, 8, 15)), isFalse);
    var inserts = 0;
    final row = await recoverRouteJourneyCapture(d, readExact: () async => saved(d),
      insert: () async { inserts++; throw StateError('must not insert'); });
    expect(row['work_date'], '2026-10-07'); expect(inserts, 0);
  });
  test('lookup failure never falls through to insert', () async {
    var inserts = 0;
    await expectLater(recoverRouteJourneyCapture(draft(), readExact: () async => throw StateError('offline'),
      insert: () async { inserts++; return {}; }), throwsStateError);
    expect(inserts, 0);
  });
  test('unknown response recovers own UUID and identical payload only', () async {
    final d = draft(); var reads = 0, inserts = 0;
    final row = await recoverRouteJourneyCapture(d, readExact: () async => ++reads == 1 ? null : saved(d),
      insert: () async { inserts++; throw StateError('response lost after commit'); });
    expect(row['id'], d.id); expect(reads, 2); expect(inserts, 1);
  });
  test('same UUID with changed source/payload never joins a different record', () async {
    final d = draft(); var inserts = 0;
    await expectLater(recoverRouteJourneyCapture(d,
      readExact: () async => {...saved(d), 'source_clock_in_id': 'another-start'},
      insert: () async { inserts++; return saved(d); }), throwsStateError);
    expect(inserts, 0);
  });
  test('collision with no exact own row remains an unknown failure', () async {
    var reads = 0;
    await expectLater(recoverRouteJourneyCapture(draft(), readExact: () async { reads++; return null; },
      insert: () async => throw StateError('23505')), throwsStateError);
    expect(reads, 2);
  });
  test('route PDF provenance keeps bucket, stop, true address and observation separate', () {
    DailyReportPdfEvidence evidence(String bucket) => DailyReportPdfEvidence(record:
      DailyReportEvidenceRecord(id: 'checkpoint', workerName: '本人', eventType: 'route_stop',
        confirmedAt: DateTime(2026, 10, 9, 9), storagePath: 'same-path', storageBucket: bucket,
        sourceClockInId: 'original-start', routeStopId: 'actual-stop', stopLabel: '登録済み現場名',
        originKind: 'direct', capturedAddress: '実GPS住所', photoObservedAt: DateTime(2026, 10, 9, 8),
        photoStatus: 'uploaded', gpsStatus: 'acquired'));
    final route = evidence('attendance-route-evidence');
    expect(route.captions.join('\n'), contains('途中現場'));
    expect(route.captions.join('\n'), contains('撮影住所: 実GPS住所'));
    expect(route.captions.join('\n'), contains('撮影日時未取得'));
    expect(route.captions.join('\n'), isNot(contains('撮影日時: 2026')));
    expect(jsonEncode(route.fingerprintData), isNot(jsonEncode(evidence('attendance-evidence').fingerprintData)));
  });
}

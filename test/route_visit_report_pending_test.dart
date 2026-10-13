import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/route_journey_capture_draft.dart';

void main() {
  RouteJourneyCaptureDraft move() => RouteJourneyCaptureDraft(
    userId: 'actor',
    companyId: 'company',
    sourceId: 'source',
    stopId: 'stop',
    originKind: 'company',
    visitKind: 'end',
    startCaptureId: 'arrival',
    payload: {
      'capture_contract_version': 1,
      'attempted_at': '2026-10-11T01:00:00Z',
      'photo_capture_status': 'not_required',
      'gps_capture_status': 'not_required',
    },
  );
  Map<String, dynamic> row(RouteJourneyCaptureDraft draft) => {
    'id': draft.id,
    'created_by': draft.userId,
    'company_id': draft.companyId,
    'source_clock_in_id': draft.sourceId,
    'route_stop_id': draft.stopId,
    'origin_kind': draft.originKind,
    'visit_kind': 'end',
    'start_capture_id': draft.startCaptureId,
    'work_date': '2026-10-11',
    'recorded_at': '2026-10-11T01:00:00Z',
    'payload': draft.payload,
  };
  test('saved move report decision survives restart with fixed visit and no new command', () {
    final draft = move();
    final saved = RouteVisitReportPending.fromSaved(draft, row(draft));
    final creating = saved.withChoice('create');
    final restored = RouteVisitReportPending.restore(creating.encoded);
    expect(restored.choice, 'create');
    expect(restored.endCaptureId, draft.id);
    expect(restored.startCaptureId, 'arrival');
    expect(restored.sourceId, 'source');
    expect(restored.stopId, 'stop');
    expect(restored.workDate, '2026-10-11');
    expect(restored.move.encoded, draft.encoded);
    expect(restored.move.payload['photo_capture_status'], 'not_required');
  });
  test('different move proof or arrival cannot create report pending', () {
    final draft = move();
    for (final field in [
      'id',
      'company_id',
      'created_by',
      'source_clock_in_id',
      'route_stop_id',
      'start_capture_id',
    ]) {
      expect(
        () => RouteVisitReportPending.fromSaved(draft, {
          ...row(draft),
          field: 'other',
        }),
        throwsStateError,
      );
    }
    final arrival = RouteJourneyCaptureDraft(
      userId: 'actor',
      companyId: 'company',
      sourceId: 'source',
      stopId: 'stop',
      originKind: 'company',
      visitKind: 'start',
      payload: {'capture_contract_version': 1},
    );
    expect(
      () => RouteVisitReportPending.fromSaved(arrival, row(arrival)),
      throwsStateError,
    );
  });
  test('same stop repeated in one day has separate fixed end identity', () {
    final first = move();
    final second = move();
    final a = RouteVisitReportPending.fromSaved(first, row(first));
    final b = RouteVisitReportPending.fromSaved(second, row(second));
    expect(a.stopId, b.stopId);
    expect(a.workDate, b.workDate);
    expect(a.endCaptureId == b.endCaptureId, false);
  });
  test('unsupported local terminal flags never clear pending', () {
    final draft = move();
    final pending = RouteVisitReportPending.fromSaved(draft, row(draft));
    final data = jsonDecode(pending.encoded) as Map;
    for (final choice in ['signed', 'done', 'cancelled', '']) {
      expect(
        () => RouteVisitReportPending.restore(
          jsonEncode({...data, 'choice': choice}),
        ),
        throwsStateError,
      );
    }
    expect(pending.withChoice('skip').choice, 'skip');
    expect(() => pending.withChoice('signed'), throwsArgumentError);
  });
}

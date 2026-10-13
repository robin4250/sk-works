import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/route_journey_capture_draft.dart';

RouteJourneyCaptureDraft draft(String? kind, {String? start}) =>
    RouteJourneyCaptureDraft(
      userId: 'user',
      companyId: 'company',
      sourceId: 'source',
      stopId: 'stop',
      originKind: 'company',
      visitKind: kind,
      startCaptureId: start,
      payload: {'capture_contract_version': 1},
    );
void main() {
  test(
    'start retry keeps the original generated command as visit identity',
    () {
      final first = draft('start');
      final restored = RouteJourneyCaptureDraft.restore(first.encoded);
      expect(restored.encoded, first.encoded);
      expect(restored.visitKind, 'start');
      expect(restored.visitStartId, first.id);
    },
  );
  test(
    'end retry preserves exact start identity and never turns into a new start',
    () {
      final end = draft('end', start: 'previous-start');
      final restored = RouteJourneyCaptureDraft.restore(end.encoded);
      expect(restored.visitKind, 'end');
      expect(restored.visitStartId, 'previous-start');
      expect(restored.id, end.id);
      final row = <String, dynamic>{
        'id': end.id,
        'created_by': 'user',
        'company_id': 'company',
        'source_clock_in_id': 'source',
        'route_stop_id': 'stop',
        'origin_kind': 'company',
        'work_date': '2026-10-10',
        'recorded_at': '2026-10-10T01:00:00Z',
        'payload': end.payload,
        'visit_kind': 'end',
        'start_capture_id': 'previous-start',
      };
      expect(restored.matchesRow(row), isTrue);
      expect(
        restored.matchesRow({...row, 'start_capture_id': 'another-start'}),
        isFalse,
      );
      expect(restored.matchesRow({...row, 'visit_kind': 'start'}), isFalse);
    },
  );
  test(
    'old pending photos stay version one without inferred visit actions',
    () {
      final old = draft(null);
      final restored = RouteJourneyCaptureDraft.restore(old.encoded);
      expect(restored.visitKind, isNull);
      expect(restored.encoded, old.encoded);
      final malformed = jsonDecode(old.encoded) as Map<String, dynamic>;
      malformed['visit_kind'] = 'end';
      expect(
        () => RouteJourneyCaptureDraft.restore(jsonEncode(malformed)),
        throwsStateError,
      );
    },
  );
  test('missing end target and inconsistent restored start are rejected', () {
    expect(() => draft('end'), throwsArgumentError);
    final malformed =
        jsonDecode(draft('start').encoded) as Map<String, dynamic>;
    malformed['start_capture_id'] = 'another-start';
    expect(
      () => RouteJourneyCaptureDraft.restore(jsonEncode(malformed)),
      throwsStateError,
    );
  });
}

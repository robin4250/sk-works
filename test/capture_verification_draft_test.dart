import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/capture_verification_draft.dart';

void main() {
  CaptureVerificationDraft draft() => CaptureVerificationDraft({
    'company_id': 'company', 'worker_id': 'worker', 'created_by': 'actor',
    'site_id': 'site', 'source_clock_in_id': 'source',
    'verification_mode': 'location_photo', 'capture_contract_version': 1,
    'gps_captured_at': '2026-10-31T22:00:00.000Z', 'photo_status': 'uploaded',
    'photo_storage_path': 'company/owned.jpg', 'latitude': 35.0, 'longitude': 139.0,
  });
  Map<String, dynamic> saved(CaptureVerificationDraft d) => {...d.payload,
    'confirmed_at': '2026-10-31T22:01:00+00:00', 'work_date': '2026-10-31'};

  test('durable restoration keeps same UUID and immutable payload', () {
    final original = draft();
    final restored = CaptureVerificationDraft.restore(original.encoded);
    expect(restored.id, original.id);
    expect(restored.encoded, original.encoded);
    expect(() => restored.payload['site_id'] = 'changed', throwsUnsupportedError);
    expect(restored.payload, isNot(contains('confirmed_at')));
    expect(restored.payload, isNot(contains('work_date')));
  });
  test('unknown response recovers exact committed own ID without another INSERT', () async {
    final d = draft();
    Map<String, dynamic>? row;
    var inserts = 0;
    final result = await recoverOrInsertCaptureDraft(d, readExact: () async => row,
      insert: () async { inserts++; row = saved(d); throw StateError('transport'); });
    expect(result['id'], d.id);
    await recoverOrInsertCaptureDraft(d, readExact: () async => row,
      insert: () async { inserts++; return saved(d); });
    expect(inserts, 1);
  });
  test('failed lookup never falls through into a new INSERT', () async {
    var inserts = 0;
    await expectLater(recoverOrInsertCaptureDraft(draft(),
      readExact: () async => throw StateError('offline'),
      insert: () async { inserts++; return {}; }), throwsStateError);
    expect(inserts, 0);
  });
  test('different source or photo cannot recover even with the same ID', () async {
    final d = draft();
    for (final key in ['source_clock_in_id', 'photo_storage_path', 'company_id', 'worker_id']) {
      final row = saved(d)..[key] = 'different';
      await expectLater(recoverOrInsertCaptureDraft(d, readExact: () async => row,
        insert: () async => throw StateError('must not insert')), throwsStateError);
    }
  });
  test('23505 retry accepts only exact payload and equivalent timestamp offset', () async {
    final d = draft();
    var reads = 0;
    final row = saved(d)..['gps_captured_at'] = '2026-11-01T07:00:00+09:00';
    final result = await recoverOrInsertCaptureDraft(d,
      readExact: () async => ++reads == 1 ? null : row,
      insert: () async => throw StateError('23505'));
    expect(result['id'], d.id);
  });  test('unknown clock-in result cannot create a new event in the next Japanese work day', () {
    final d = CaptureVerificationDraft({'event_type': 'clock_in'},
      preparedAt: DateTime.utc(2026, 10, 31, 14, 59));
    expect(d.canInsertOn(DateTime.utc(2026, 10, 31, 14, 59, 59)), isTrue);
    expect(d.canInsertOn(DateTime.utc(2026, 10, 31, 15)), isFalse);
  });

}

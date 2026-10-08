import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/capture_verification_draft.dart';
import 'package:sk_works/features/attendance/gps_photo_capture_result.dart';

void main() {
  test('actual capture INSERT metadata uses deployed migration columns for every state', () {
    final migration = File(
      'supabase/migrations/20261008173515_attendance_capture_failure_contract.sql',
    ).readAsStringSync();
    final columns = RegExp(r'add column (\w+)\s').allMatches(migration)
      .map((match) => match.group(1)!).toSet();
    const gpsStates = {
      CaptureGpsState.captured: 'acquired',
      CaptureGpsState.failed: 'failed',
      CaptureGpsState.notRegistered: 'missing',
    };
    const photoStates = {
      CapturePhotoState.uploaded: 'uploaded',
      CapturePhotoState.uploadFailed: 'upload_failed',
      CapturePhotoState.cameraFailed: 'failed',
      CapturePhotoState.captured: 'missing',
      CapturePhotoState.notRegistered: 'missing',
    };
    for (final gpsState in gpsStates.entries) {
      for (final photoState in photoStates.entries) {
        final metadata = GpsPhotoCaptureResult(
          context: const CaptureShiftContext(companyId: 'company',
            workDate: '2026-10-31', requestedMethod: 'location_photo'),
          attemptedAt: DateTime.utc(2026, 10, 31),
          gpsState: gpsState.key, photoState: photoState.key,
        ).insertMetadata;
        expect(metadata.keys.toSet(), columns,
          reason: 'Unknown PostgREST INSERT columns must fail this contract.');
        expect(metadata['gps_capture_status'], gpsState.value);
        expect(metadata['photo_capture_status'], photoState.value);
        final draft = CaptureVerificationDraft({...metadata,
          'company_id': 'company', 'worker_id': 'worker', 'created_by': 'actor',
          'verification_mode': 'location_photo'});
        final restored = CaptureVerificationDraft.restore(draft.encoded);
        expect(restored.payload, draft.payload);
        expect(restored.payload['gps_capture_status'], gpsState.value);
        expect(restored.payload['photo_capture_status'], photoState.value);
      }
    }
  });

  test('daily report reads both capture statuses using the same schema columns', () {
    final source = File('lib/features/daily_reports/daily_report_repository.dart')
      .readAsStringSync();
    expect(source, contains(',capture_contract_version,gps_capture_status,photo_capture_status,'));
    expect(source, contains("gpsStatus: raw['gps_capture_status']"));
    expect(source, contains("photoStatus: raw['photo_capture_status']"));
    expect(source, isNot(contains("raw['gps_status']")));
    expect(source, isNot(contains("raw['photo_status']")));
  });
}

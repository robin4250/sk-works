import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/gps_photo_capture_controller.dart';
import 'package:sk_works/features/attendance/gps_photo_capture_result.dart';

void main() {
  final at = DateTime.utc(2026, 10, 8, 22);
  const context = CaptureShiftContext(companyId: 'company', workDate: '2026-10-08',
    requestedMethod: 'location_photo', sourceClockInId: 'original', siteId: 'site');
  CapturedPhoto photo() => CapturedPhoto(bytes: Uint8List.fromList([1, 2]), capturedAt: at);
  CapturedGpsSample gps() => CapturedGpsSample(latitude: 35, longitude: 139,
    sampledAt: at, address: 'actual sample address');

  test('successful upload keeps original shift and never claims DB success', () async {
    final result = await GpsPhotoCaptureController(camera: () async => photo(),
      sampleGps: () async => gps(), upload: (_, shift) async {
        expect(identical(shift, context), isTrue);
        return 'owned/photo.jpg';
      }, prompt: (_) async => throw StateError('unexpected prompt'), now: () => at).capture(context);
    expect(result.context.sourceClockInId, 'original');
    expect(result.context.workDate, '2026-10-08');
    expect(result.context.requestedMethod, 'location_photo');
    expect(result.addressSource, CaptureAddressSource.liveSample);
    expect(result.attendancePersisted, isFalse);
  });
  test('GPS failure prompts before upload and preserves photo on confirm', () async {
    final events = <String>[];
    final result = await GpsPhotoCaptureController(camera: () async => photo(),
      sampleGps: () async => throw StateError('gps'), upload: (_, __) async {
        events.add('upload'); return 'owned/photo.jpg';
      }, prompt: (failure) async { events.add(failure.name); return CaptureDecision.confirm; },
      now: () => at).capture(context);
    expect(events, ['gps', 'upload']);
    expect(result.gpsState, CaptureGpsState.failed);
    expect(result.gps, isNull);
    expect(result.photo, isNotNull);
    expect(result.addressSource, CaptureAddressSource.unavailable);
  });
  test('old GPS cannot be presented as this photo location', () async {
    final result = await GpsPhotoCaptureController(camera: () async => photo(),
      sampleGps: () async => CapturedGpsSample(latitude: 35, longitude: 139,
        sampledAt: at.subtract(const Duration(hours: 1)), address: 'old'),
      upload: (_, __) async => 'owned/photo.jpg', prompt: (_) async => CaptureDecision.confirm,
      now: () => at).capture(context);
    expect(result.gpsState, CaptureGpsState.failed);
    expect(result.gps, isNull);
  });
  test('upload failure retains local draft and no storage path', () async {
    final result = await GpsPhotoCaptureController(camera: () async => photo(),
      sampleGps: () async => gps(), upload: (_, __) async => throw StateError('offline'),
      prompt: (failure) async { expect(failure, CaptureFailure.upload); return CaptureDecision.confirm; },
      now: () => at).capture(context);
    expect(result.photoState, CapturePhotoState.uploadFailed);
    expect(result.photo?.bytes, [1, 2]);
    expect(result.storagePath, isNull);
    expect(result.attendancePersisted, isFalse);
  });
  test('retake starts a new capture and does not attach failed first sample', () async {
    var cameraCount = 0;
    var gpsCount = 0;
    final result = await GpsPhotoCaptureController(camera: () async { cameraCount++; return photo(); },
      sampleGps: () async { gpsCount++; if (gpsCount == 1) { throw StateError('gps'); } return gps(); },
      upload: (_, __) async => 'owned/photo.jpg', prompt: (_) async => CaptureDecision.retake,
      now: () => at).capture(context);
    expect(cameraCount, 2);
    expect(result.gpsState, CaptureGpsState.captured);
  });
  test('cancelled camera yields missing evidence without uploading', () async {
    final result = await GpsPhotoCaptureController(camera: () async => null,
      sampleGps: () async => throw StateError('must not sample'),
      upload: (_, __) async => throw StateError('must not upload'),
      prompt: (_) async => CaptureDecision.confirm, now: () => at).capture(context);
    expect(result.photoState, CapturePhotoState.notRegistered);
    expect(result.photo, isNull);
  });
  test('confirmed camera failure stays distinct from camera cancellation', () async {
    final result = await GpsPhotoCaptureController(
      camera: () async => throw StateError('camera failed'),
      sampleGps: () async => throw StateError('must not sample'),
      upload: (_, __) async => throw StateError('must not upload'),
      prompt: (failure) async {
        expect(failure, CaptureFailure.camera);
        return CaptureDecision.confirm;
      }, now: () => at).capture(context);
    expect(result.photoState, CapturePhotoState.cameraFailed);
    expect(result.photo, isNull);
    expect(result.attendancePersisted, isFalse);
  });

}

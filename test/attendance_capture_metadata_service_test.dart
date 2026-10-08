import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/attendance_capture_metadata_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('sko.capture_metadata');
  const service = AttendanceCaptureMetadataService(platform: TargetPlatform.iOS);
  final calls = <MethodCall>[];
  Object? response;
  setUp(() {
    calls.clear();
    response = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return response;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

  test('retains captured coordinates and nullable address without site fallback', () async {
    expect(await service.reverseGeocodeCapturedLocation(latitude: 35.1, longitude: 139.2), isNull);
    expect(calls.single.arguments, {'latitude': 35.1, 'longitude': 139.2});
    response = '  Tokyo  ';
    expect(await service.reverseGeocodeCapturedLocation(latitude: 35.1, longitude: 139.2), 'Tokyo');
  });
  test('rejects impossible coordinates before platform invocation', () async {
    expect(await service.reverseGeocodeCapturedLocation(latitude: double.nan, longitude: 0), isNull);
    expect(await service.reverseGeocodeCapturedLocation(latitude: 0, longitude: 181), isNull);
    expect(calls, isEmpty);
  });
  test('requires known UTC timestamp and rejects normalized impossible dates', () async {
    for (final bad in ['2026-10-09T08:00:00', '2026-02-30T08:00:00Z', 42]) {
      response = bad;
      expect(await service.readPhotoCapturedAt('/tmp/photo.jpg'), isNull);
    }
    response = '2026-10-08T23:00:00Z';
    expect(await service.readPhotoCapturedAt('/tmp/photo.jpg'), DateTime.utc(2026, 10, 8, 23));
  });
  test('non-iOS explicitly unavailable and relative paths rejected', () async {
    const android = AttendanceCaptureMetadataService(platform: TargetPlatform.android);
    expect(await android.readPhotoCapturedAt('/tmp/photo.jpg'), isNull);
    expect(await service.readPhotoCapturedAt('photo.jpg'), isNull);
    expect(calls, isEmpty);
  });
  test('platform failure remains optional enrichment', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (_) async => throw PlatformException(code: 'network'));
    expect(await service.reverseGeocodeCapturedLocation(latitude: 35, longitude: 139), isNull);
  });
}

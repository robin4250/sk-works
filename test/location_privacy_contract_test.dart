import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('manual attendance remains one-shot location only', () {
    final source =
        File('lib/features/attendance/attendance_verification_page.dart')
            .readAsStringSync();

    expect(source, contains('Geolocator.getCurrentPosition'));
    expect(source, isNot(contains('Geolocator.getPositionStream')));
  });

  test('GPS auto attendance background stream is isolated to opt-in service', () {
    final source = File(
      'lib/features/attendance/gps_auto_attendance_service.dart',
    ).readAsStringSync();

    expect(source, contains('Geolocator.getPositionStream'));
    expect(source, contains('LocationPermission.always'));
    expect(source, contains('allowBackgroundLocationUpdates: true'));
    expect(source, contains('showBackgroundLocationIndicator: true'));
  });

  test('iOS preparation explains and enables GPS auto background location', () {
    final script = File('tool/prepare_ios.sh').readAsStringSync();

    expect(script, contains('NSLocationWhenInUseUsageDescription'));
    expect(script, contains('NSLocationAlwaysAndWhenInUseUsageDescription'));
    expect(script, contains('background_modes.append("location")'));
  });
}

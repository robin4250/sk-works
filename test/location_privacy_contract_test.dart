import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('attendance location remains action-only without background tracking', () {
    final source =
        File('lib/features/attendance/attendance_verification_page.dart')
            .readAsStringSync();

    expect(source, contains('Geolocator.getCurrentPosition'));
    expect(source, isNot(contains('Geolocator.getPositionStream')));
    expect(source, isNot(contains('LocationPermission.always')));
    expect(source, isNot(contains('requestTemporaryFullAccuracy')));
  });

  test('iOS preparation asks only for when-in-use location permission', () {
    final script = File('tool/prepare_ios.sh').readAsStringSync();

    expect(script, contains('NSLocationWhenInUseUsageDescription'));
    expect(
      script,
      contains('data.pop("NSLocationAlwaysUsageDescription", None)'),
    );
    expect(
      script,
      contains(
        'data.pop("NSLocationAlwaysAndWhenInUseUsageDescription", None)',
      ),
    );
    expect(script, contains('mode != "location"'));
  });
}

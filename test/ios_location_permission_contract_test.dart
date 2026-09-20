import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS preparation strips Always/background location configuration', () {
    final source = File('tool/prepare_ios.sh').readAsStringSync();

    expect(source, contains('NSLocationWhenInUseUsageDescription'));
    expect(source, contains('data.pop("NSLocationAlwaysUsageDescription"'));
    expect(
      source,
      contains('data.pop("NSLocationAlwaysAndWhenInUseUsageDescription"'),
    );
    expect(source, contains('mode != "location"'));
  });
}

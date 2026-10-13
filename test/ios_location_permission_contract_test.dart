import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS preparation supports opt-in GPS auto attendance background location', () {
    final source = File('tool/prepare_ios.sh').readAsStringSync();

    expect(source, contains('NSLocationWhenInUseUsageDescription'));
    expect(source, contains('NSLocationAlwaysAndWhenInUseUsageDescription'));
    expect(source, contains('UIBackgroundModes'));
    expect(source, contains('background_modes.append("location")'));
    expect(source, isNot(contains('data.pop("NSLocationAlwaysAndWhenInUseUsageDescription"')));
  });
}

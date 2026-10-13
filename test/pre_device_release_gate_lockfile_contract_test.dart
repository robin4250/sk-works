import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pre-device release gate verifies lockfile resolution', () {
    final source =
        File('tool/pre_device_release_gate.sh').readAsStringSync();

    expect(source, contains('flutter pub get'));
    expect(source, contains('git diff --exit-code -- pubspec.lock'));
    expect(source, contains('pubspec.lock is stable'));
  });
}

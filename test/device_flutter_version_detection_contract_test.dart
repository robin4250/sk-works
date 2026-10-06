import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('device-day helpers tolerate blank lines before Flutter version', () {
    for (final path in [
      'tool/mac_first_run.sh',
      'tool/pre_device_release_gate.sh',
      'tool/device_day_preflight.sh',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains("sed -nE 's/.*Flutter[[:space:]]+"));
      expect(source, isNot(contains("head -n 1 | awk '{print \\$2}'")));
    }
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pre-device release gate requires Flutter 3.47.5', () {
    final source =
        File('tool/pre_device_release_gate.sh').readAsStringSync();

    expect(source, contains('flutter --version'));
    expect(source, contains('SKO基準は3.47.5'));
    expect(source, contains('[[ "$flutter_version" != "3.47.5" ]]'));
  });
}

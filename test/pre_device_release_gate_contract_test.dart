import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pre-device release gate covers critical local contracts', () {
    final source =
        File('tool/pre_device_release_gate.sh').readAsStringSync();

    expect(source, contains('check_dependency_pins.sh'));
    expect(source, contains('check_no_client_secrets.sh'));
    expect(source, contains('check_migration_files.sh'));
    expect(source, contains("find tool -maxdepth 1 -type f -name '*.sh'"));
    expect(source, contains('flutter analyze'));
    expect(source, contains('flutter test'));
  });
}

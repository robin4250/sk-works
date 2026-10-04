import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('post-594 Release candidate keeps original SKO bundle id', () {
    final prepare = read('tool/prepare_ios.sh');
    final runner = read('tool/run_ios_device.sh');
    final record = read('docs/PRE_DEVICE_RELEASE_CANDIDATE_20261004.md');

    expect(prepare, contains('BUNDLE_ID="com.skworks.skWorks"'));
    expect(runner, contains('EXPECTED_BUNDLE_ID="com.skworks.skWorks"'));
    expect(record, contains('com.skworks.skWorks'));
    expect(record, contains('Never install to `com.robin4250.sko`'));
  });

  test('post-594 Release candidate is Release-only', () {
    final record = read('docs/PRE_DEVICE_RELEASE_CANDIDATE_20261004.md');
    expect(record, contains('Release only; no Debug / flutter run'));
    expect(record, contains('#594 printable payment certificate PDF'));
    expect(record, contains('#595 payroll review menu connection'));
  });
}

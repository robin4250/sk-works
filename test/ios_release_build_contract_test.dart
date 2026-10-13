import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS CI verifies a Release build before device install', () {
    final workflow =
        File('.github/workflows/ios-ci.yml').readAsStringSync();
    final device =
        File('tool/run_ios_device.sh').readAsStringSync();

    expect(
      workflow,
      contains('flutter build ios --release --no-codesign'),
    );
    expect(device, contains('com.skworks.skWorks'));
    expect(device, contains('BUILT_BUNDLE_ID'));
  });
}

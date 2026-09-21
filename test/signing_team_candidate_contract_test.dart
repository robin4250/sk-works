import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('device-day helper surfaces a detected Apple Team ID candidate', () {
    final assistant =
        File('tool/ios_install_assistant.sh').readAsStringSync();
    final diagnostics =
        File('tool/collect_ios_diagnostics.sh').readAsStringSync();

    expect(assistant, contains('Signing Team候補'));
    expect(assistant, contains('[A-Z0-9]{10}'));
    expect(diagnostics, contains('Detected Team ID candidates'));
    expect(assistant, contains('xcodebuild -checkFirstLaunchStatus'));
    expect(assistant, contains('xcodebuild -showsdks'));
    expect(assistant, contains('sudo xcodebuild -runFirstLaunch'));
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('device-day diagnostics distinguish USB, Xcode, and Flutter visibility', () {
    final assistant =
        File('tool/ios_install_assistant.sh').readAsStringSync();
    final diagnostics =
        File('tool/collect_ios_diagnostics.sh').readAsStringSync();

    expect(assistant, contains('xcrun devicectl list devices'));
    expect(assistant, contains('system_profiler SPUSBDataType'));
    expect(assistant, contains('XcodeはiPhoneを認識しています'));
    expect(assistant, contains('USBではiPhoneを検出しています'));
    expect(diagnostics, contains('xcodebuild -checkFirstLaunchStatus'));
    expect(diagnostics, contains('Resolved Runner build settings'));
  });
}

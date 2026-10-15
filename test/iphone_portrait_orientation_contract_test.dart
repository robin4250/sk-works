import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS permits signature rotation while runtime keeps normal iPhone UI portrait', () {
    final source = File('tool/prepare_ios.sh').readAsStringSync();

    expect(source, contains('UISupportedInterfaceOrientations'));
    expect(source, contains('UIInterfaceOrientationPortrait'));
    expect(source, contains('UIInterfaceOrientationLandscapeLeft'));
    expect(source, contains('UIInterfaceOrientationLandscapeRight'));
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('SkoOrientationPolicy.initialize'));
    final capture = File('lib/features/daily_reports/signature_capture_page.dart').readAsStringSync();
    expect(capture, contains('SkoOrientationPolicy.enterSignature'));
    expect(capture, contains('SkoOrientationPolicy.leaveSignature'));
  });
}

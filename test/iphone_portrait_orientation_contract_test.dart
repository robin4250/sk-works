import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS preparation locks iPhone UI to portrait', () {
    final source = File('tool/prepare_ios.sh').readAsStringSync();

    expect(source, contains('UISupportedInterfaceOrientations'));
    expect(source, contains('UIInterfaceOrientationPortrait'));
    expect(source, isNot(contains('UIInterfaceOrientationLandscapeLeft')));
    expect(source, isNot(contains('UIInterfaceOrientationLandscapeRight')));
  });
}

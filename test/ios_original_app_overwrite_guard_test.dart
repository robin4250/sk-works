import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release install refuses a mismatched built app bundle id', () {
    final source = File('tool/run_ios_device.sh').readAsStringSync();

    expect(source, contains('/usr/libexec/PlistBuddy'));
    expect(source, contains('CFBundleIdentifier'));
    expect(source, contains('com.skworks.skWorks'));
    expect(source, contains('別SKOを増やさないため'));
    expect(
      source.indexOf('BUILT_BUNDLE_ID'),
      lessThan(source.indexOf('xcrun devicectl device install app')),
    );
  });
}

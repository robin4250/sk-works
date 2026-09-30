import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('device-day installs a standalone iPhone Release build', () {
    final run = File('tool/run_ios_device.sh').readAsStringSync();
    final debug = File('tool/run_ios_device_debug.sh').readAsStringSync();
    final day = File('tool/device_day.sh').readAsStringSync();

    expect(run, contains('flutter build ios'));
    expect(run, contains('--release'));
    expect(run, contains('xcrun devicectl device install app'));
    expect(run, contains('xcrun devicectl device process launch'));
    expect(run, isNot(contains('exec flutter run')));

    expect(debug, contains('exec flutter run'));
    expect(day, contains('Release版をiPhoneへインストール'));
  });
}

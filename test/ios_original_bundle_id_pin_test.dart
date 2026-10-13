import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS device workflow pins the original installed SKO bundle id', () {
    for (final path in [
      'tool/prepare_ios.sh',
      'tool/check_ios_generated_contract.sh',
      'tool/run_ios_device.sh',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains('com.skworks.skWorks'));
      expect(source, isNot(contains(r'${SKO_IOS_BUNDLE_ID:-com.skworks.skWorks}')));
    }
  });

  test('device-day workflow stays release-only', () {
    final deviceDay = File('tool/device_day.sh').readAsStringSync();
    final preflight = File('tool/device_day_preflight.sh').readAsStringSync();
    final installer = File('tool/run_ios_device.sh').readAsStringSync();

    expect(deviceDay, contains('bash tool/run_ios_device.sh'));
    expect(preflight, contains('flutter build ios --release --no-codesign'));
    expect(preflight, isNot(contains('flutter build ios --debug')));
    expect(installer, contains('--release'));
    expect(installer, isNot(contains('flutter run')));
  });

}

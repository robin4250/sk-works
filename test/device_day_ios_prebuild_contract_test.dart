import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('device-day preflight builds iOS before signed device launch', () {
    final preflight =
        File('tool/device_day_preflight.sh').readAsStringSync();
    final diagnostics =
        File('tool/collect_ios_diagnostics.sh').readAsStringSync();

    final buildIndex =
        preflight.indexOf('flutter build ios --debug --no-codesign');
    final assistantIndex =
        preflight.indexOf('bash tool/ios_install_assistant.sh');

    expect(buildIndex, greaterThanOrEqualTo(0));
    expect(assistantIndex, greaterThan(buildIndex));
    expect(preflight, contains('bash tool/check_ios_generated_contract.sh'));
    expect(preflight, contains('Podfile.lock'));
    expect(diagnostics, contains('ios/Podfile.lock'));
  });
}

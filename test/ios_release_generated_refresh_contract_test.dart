import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release device runner always reapplies generated iOS settings', () {
    final source = File('tool/run_ios_device.sh').readAsStringSync();

    expect(
      source,
      contains('bash tool/prepare_ios.sh'),
    );
    expect(
      source,
      contains('bash tool/check_ios_generated_contract.sh'),
    );
    expect(
      source.indexOf('bash tool/prepare_ios.sh'),
      lessThan(source.indexOf('flutter build ios')),
    );
    expect(
      source.indexOf('bash tool/check_ios_generated_contract.sh'),
      lessThan(source.indexOf('flutter build ios')),
    );
  });
}

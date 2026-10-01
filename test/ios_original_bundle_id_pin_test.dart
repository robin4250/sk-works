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
}

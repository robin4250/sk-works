import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS preparation strips broad ATS bypasses', () {
    final source = File('tool/prepare_ios.sh').readAsStringSync();

    expect(source, contains('NSAppTransportSecurity'));
    expect(source, contains('NSAllowsArbitraryLoads'));
    expect(source, contains('NSAllowsArbitraryLoadsInWebContent'));
    expect(source, contains('.pop("NSAllowsArbitraryLoads", None)'));
  });
}

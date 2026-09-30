import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('final pre-device readiness reflects the integrated TestFlight candidate', () {
    final readiness =
        File('docs/PRE_DEVICE_READINESS.md').readAsStringSync();
    final record =
        File('docs/IPHONE_TEST_RUN_RECORD.md').readAsStringSync();

    expect(readiness, contains('Status date: 2026-09-30'));
    expect(readiness, contains('exactly one site chat'));
    expect(readiness, contains('Vehicle/route persistence'));
    expect(readiness, contains('Master role + trusted device'));
    expect(readiness, contains('15 minutes'));
    expect(readiness, contains('Japan Country Pack'));
    expect(readiness, contains('company name, address, corporate number, and SKO company ID'));
    expect(readiness, contains('3 `auth_rls_initplan` WARN items'));
    expect(readiness, contains('vehicles` and `route_assignments'));
    expect(readiness, contains('SKO pre-device database security assertions passed'));
    expect(record, contains('A〜Oの受入項目を確認'));
  });
}

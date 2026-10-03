import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('secondary auth keeps biometric entry visible after password unlock', () {
    final source = File(
      'lib/features/auth/secondary_protected_page.dart',
    ).readAsStringSync();

    expect(source, contains('if (_biometricAvailable) ...['));
    expect(
      source,
      isNot(contains('if (_biometricEnabled && _biometricAvailable) ...[')),
    );
    expect(source, contains("'sko_secondary_biometric_enabled_$userId'"));
    expect(source, contains('_biometricEnabled = true;'));
    expect(source, contains('Face ID / Touch IDで開く'));
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('secondary password unlock never disables biometric entry', () {
    final source = File(
      'lib/features/auth/secondary_protected_page.dart',
    ).readAsStringSync();

    expect(source, contains('getAvailableBiometrics'));
    expect(source, contains('AppLifecycleState.resumed'));
    expect(source, contains('_refreshBiometricAvailability'));
    expect(
      source,
      contains('Password unlock must never disable or hide Face ID / Touch ID'),
    );
    expect(
      source,
      isNot(
        contains(
          "setBool('sko_secondary_biometric_enabled_\$userId', false)",
        ),
      ),
    );
    expect(source, contains('if (_biometricAvailable)'));
  });
}

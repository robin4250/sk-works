import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Master protected page requires trust biometric and second password', () {
    final page =
        File('lib/features/settings/master_protected_page.dart').readAsStringSync();
    final repository =
        File('lib/features/settings/master_device_repository.dart').readAsStringSync();

    expect(repository, contains("'current_master_device_status'"));
    expect(repository, contains("'bootstrap_first_master_device'"));
    expect(page, contains('biometricOnly: true'));
    expect(page, contains('verifySecondaryPassword'));
    expect(page, contains('MasterStepUpPolicy.requiresFreshAuthentication'));
    expect(page, contains('trustedDevice: _trustedDevice'));
    expect(page, contains('secondPasswordVerified: secondPasswordVerified'));
    expect(page, contains('biometricVerified: biometricVerified'));
    expect(page, contains('MasterStepUpPolicy.sessionDuration'));
  });

  test('Master step-up clears when app leaves foreground', () {
    final page =
        File('lib/features/settings/master_protected_page.dart').readAsStringSync();

    expect(page, contains('AppLifecycleState.inactive'));
    expect(page, contains('AppLifecycleState.paused'));
    expect(page, contains('AppLifecycleState.hidden'));
    expect(page, contains('_lock();'));
  });
}

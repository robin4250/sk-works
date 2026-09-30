import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('untrusted Master devices can enter emergency recovery only through the dedicated route', () {
    final protected = File(
      'lib/features/settings/master_protected_page.dart',
    ).readAsStringSync();

    expect(protected, contains('MasterEmergencyRecoveryPage'));
    expect(protected, contains('!_trustedDevice && !_canBootstrap'));
    expect(protected, contains('信頼済み端末を使えない場合は緊急復旧'));
    expect(protected, contains('final recovered = await Navigator.of(context).push<bool>'));
    expect(protected, contains('await _load();'));
    expect(protected, isNot(contains('_trustedDevice = true;\n    Navigator')));
  });

  test('Master emergency recovery requires biometric second password and both codes', () {
    final page = File(
      'lib/features/settings/master_emergency_recovery_page.dart',
    ).readAsStringSync();
    final repository = File(
      'lib/features/settings/master_recovery_repository.dart',
    ).readAsStringSync();

    expect(page, contains('biometricOnly: true'));
    expect(page, contains('verifySecondaryPassword'));
    expect(page, contains('startEmergencyRecovery'));
    expect(page, contains("channel: 'primary'"));
    expect(page, contains("channel: 'secondary'"));
    expect(page, contains('if (!secondary.complete)'));
    expect(page, contains('consumeRecoveryChallenge'));

    expect(repository, contains("'send-master-recovery-codes'"));
    expect(repository, contains("'verify_master_recovery_code'"));
    expect(repository, contains("'consume_master_recovery_challenge'"));
    expect(repository, contains("raw['trusted'] != true"));
  });

  test('recovery success registers the device then returns to normal Master gate', () {
    final page = File(
      'lib/features/settings/master_emergency_recovery_page.dart',
    ).readAsStringSync();
    final protected = File(
      'lib/features/settings/master_protected_page.dart',
    ).readAsStringSync();

    expect(page, contains('Navigator.of(context).pop(true)'));
    expect(protected, contains('_unlocked = false'));
    expect(protected, contains('await _load();'));
    expect(protected, contains('Face ID / Touch ID＋第2パスで開く'));
  });
}

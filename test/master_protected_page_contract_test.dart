import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
void main() {
  test('Master entry shares secondary verifier but preserves server device and role authorization', () {
    final page = File('lib/features/settings/master_protected_page.dart').readAsStringSync();
    final repository = File('lib/features/settings/master_device_repository.dart').readAsStringSync();
    expect(repository, contains("'current_master_device_status'"));
    expect(repository, contains("'bootstrap_first_master_device'"));
    expect(page, contains("client.rpc('verify_secondary_password'"));
    expect(page, contains("'p_password': password"));
    expect(page, contains('MasterSecondaryEntryPolicy.allows'));
    expect(page, contains('passwordVerified && biometricVerified'));
    expect(page, contains('passwordVerified || biometricEnabled && biometricVerified'));
    expect(page, contains('MasterStepUpPolicy.sessionDuration'));
    expect(page, isNot(contains('setSecondaryPassword(')));
  });
  test('native prompt inactive is distinct from background and attempt is invalidated on lock', () {
    final page = File('lib/features/settings/master_protected_page.dart').readAsStringSync();
    expect(page, contains('state == AppLifecycleState.inactive && _nativePrompt'));
    expect(page, contains('state != AppLifecycleState.resumed) _lock();'));
    expect(page, contains('_generation++;'));
    expect(page, contains('String password = _password.text;\n    _password.clear();'));
  });
}

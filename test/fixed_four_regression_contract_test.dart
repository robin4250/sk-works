import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('onboarding approval stays inside the single 承認待ち entry', () {
    final app = File('lib/app_v2.dart').readAsStringSync();
    final hub =
        File('lib/features/approvals/approvals_hub_page.dart').readAsStringSync();
    final settings = File(
      'lib/features/settings/company_module_settings_repository.dart',
    ).readAsStringSync();

    expect(app, contains("key: 'approvals'"));
    expect(app, contains("label: SkoLanguageController.tr('承認待ち')"));
    expect(app, isNot(contains("label: SkoLanguageController.tr('本登録承認')")));
    expect(hub, contains('日報の承認待ち'));
    expect(hub, contains('従業員の本登録承認'));
    expect(settings, contains("'approvals'"));
    expect(settings, isNot(contains("'onboarding_approvals'")));
  });

  test('secondary password never hides the biometric entry', () {
    final source = File(
      'lib/features/auth/secondary_protected_page.dart',
    ).readAsStringSync();

    expect(source, contains('if (_biometricAvailable) ...['));
    expect(
      source,
      isNot(contains('if (_biometricEnabled && _biometricAvailable) ...[')),
    );
    expect(source, contains('Face ID / Touch IDで開く'));
    expect(source, contains(r"'sko_secondary_biometric_enabled_$userId'"));
  });
}

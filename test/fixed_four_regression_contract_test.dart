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

    expect(app, contains("case 'approvals':"));
    expect(app, contains("_identity.can('can_approve_daily_report_edits')"));
    expect(app, isNot(contains("key: 'approvals'")));
    expect(app, contains('ApprovalsHubPage'));
    expect(app, isNot(contains("label: SkoLanguageController.tr('本登録承認')")));
    expect(hub, contains('日報の承認待ち'));
    expect(hub, contains('従業員の本登録承認'));
    expect(settings, contains("'approvals'"));
    expect(settings, isNot(contains("'onboarding_approvals'")));
  });

  test('secondary password keeps biometric entry unless server requires fresh password', () {
    final source = File(
      'lib/features/auth/secondary_protected_page.dart',
    ).readAsStringSync();

    expect(source, contains('if (_biometricAvailable && _entryAccess?.requiredByServer != true) ...['));
    expect(
      source,
      isNot(contains('if (_biometricEnabled && _biometricAvailable) ...[')),
    );
    expect(source, contains('Face ID / Touch IDで開く'));
    expect(source, contains(r"'sko_secondary_biometric_enabled_$userId'"));
  });
}


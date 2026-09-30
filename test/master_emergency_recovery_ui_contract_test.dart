import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Master recovery contacts UI is protected and confirmation based', () {
    final settings =
        File('lib/features/settings/settings_page.dart').readAsStringSync();
    final page = File(
      'lib/features/settings/master_recovery_contacts_page.dart',
    ).readAsStringSync();
    final repository = File(
      'lib/features/settings/master_recovery_repository.dart',
    ).readAsStringSync();
    final devices = File(
      'lib/features/settings/master_device_repository.dart',
    ).readAsStringSync();

    expect(settings, contains('MasterRecoveryContactsPage'));
    expect(settings, contains("title: 'Master 緊急復旧設定'"));
    expect(settings, contains('MasterProtectedPage'));
    expect(page, contains('復旧用メールを変更しますか？'));
    expect(page, contains('異なる2つのメールアドレスを登録してください。'));
    expect(page, contains('変更は監査ログへ記録されます'));
    expect(repository, contains("'current_master_recovery_contacts'"));
    expect(repository, contains("'set_master_recovery_contacts'"));
    expect(repository, contains("'p_device_key': deviceKey"));
    expect(devices, contains("sko_master_device_key_$userId"));
  });

  test('Master recovery page never displays raw configured addresses', () {
    final page = File(
      'lib/features/settings/master_recovery_contacts_page.dart',
    ).readAsStringSync();

    expect(page, contains('primaryMasked'));
    expect(page, contains('secondaryMasked'));
    expect(page, isNot(contains('primaryEmail ??')));
    expect(page, isNot(contains('secondaryEmail ??')));
  });
}

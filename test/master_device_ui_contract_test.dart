import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('master device repository uses protected RPCs', () {
    final repository =
        read('lib/features/settings/master_device_repository.dart');

    expect(repository, contains("'current_master_admin_status'"));
    expect(repository, contains("'master_device_rows'"));
    expect(repository, contains("'set_master_device_locked'"));
    expect(repository, contains("'revoke_master_device'"));
  });

  test('master device page shows status and protected actions', () {
    final page =
        read('lib/features/settings/master_device_management_page.dart');

    expect(page, contains('マスターデバイス管理'));
    expect(page, contains('登録日時'));
    expect(page, contains('最終利用'));
    expect(page, contains('ロック解除'));
    expect(page, contains('登録解除'));
    expect(page, contains('新端末の登録フローは次の実装で追加します。'));
  });

  test('settings entry is shown only after master admin check', () {
    final settings = read('lib/features/settings/settings_page.dart');

    expect(settings, contains('_isMasterAdmin'));
    expect(settings, contains('isMasterAdmin()'));
    expect(settings, contains("if (_isMasterAdmin)"));
    expect(settings, contains('MasterDeviceManagementPage'));
  });
}

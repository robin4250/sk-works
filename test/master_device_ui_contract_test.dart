import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();
String compact(String source) => source.replaceAll(RegExp(r'\s+'), '');

void main() {
  test('master device repository uses protected RPCs', () {
    final repository =
        read('lib/features/settings/master_device_repository.dart');

    final owner = read('lib/features/settings/master_owner_access.dart');
    final guard = read('lib/features/auth/secondary_reset_session_guard.dart');
    expect(compact(repository), contains(compact('''await session?.check();
    accessToken = session?.accessToken ?? accessToken;
    final allowed = await MasterOwnerAccess.check(_client, accessToken: accessToken);
    await session?.check();
    return allowed;''')));
    expect(owner, contains("rpc('current_master_admin_status')"));
    expect(compact(owner), contains('ownerId.isNotEmpty&&session!=null&&!session.isExpired&&session.user.id==ownerId&&SecondaryResetSessionGuard.identityOf(session)!=null'));
    expect(compact(owner), contains(compact('''final captured = client.auth.currentSession;
    if (!allows(captured) || (accessToken != null && accessToken != captured!.accessToken)) { return false; }
    final token = captured!.accessToken;''')));
    expect(owner, contains(".setHeader('Authorization', 'Bearer \$token')"));
    expect(compact(owner), contains("returnallows(now)&&identical(now,captured)&&now!.accessToken==token&&rawisMap&&raw['is_master_admin']==true;"));
    expect(compact(owner), contains("SecondaryResetSessionGuard.identityOf(session)=='\$actor/\$sid'"));
    expect(compact(guard), contains("claims['sub']!=session.user.id"));
    expect(guard, contains("claims['session_id']"));
    expect(compact(guard), contains("claims['role']!='authenticated'"));
    expect(owner, isNot(contains('String.fromEnvironment')));
    expect(owner, isNot(contains('userMetadata')));
    expect(owner, isNot(contains('appMetadata')));
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
    expect(compact(settings), contains('if(_isMasterAdmin&&MasterOwnerAccess.currentFor(_client))'));
    expect(compact(settings), contains(compact('''final master = await masterRepository.isMasterAdmin();
        check();
        _isMasterAdmin = master;''')));
    expect(compact(settings), contains('!identical(session,_client!.auth.currentSession)'));
    expect(compact(settings), contains('generation!=_loadGeneration'));
    expect(settings, contains('MasterProtectedPage'));
    expect(settings, contains('MasterDeviceManagementPage'));
  });
}

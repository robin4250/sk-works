import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/auth/app_auth_storage_owner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('synthetic-auth-vault-test');
  tearDown(() { TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
    .setMockMethodCallHandler(channel, null); });

  test('missing channel acknowledgement is unknown rather than successful', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (_) async => null);
    final vault = NativeAuthSessionVault(project: 'project', channel: channel);
    await expectLater(vault.write('synthetic envelope'), throwsStateError);
    await expectLater(vault.read(), throwsStateError);
  });

  test('only exact protocol responses are accepted', () async {
    for (final reply in <Object?>[
      {'status': 'absent', 'envelope': 'stale'},
      {'status': 'present'},
      {'status': 'present', 'envelope': 123},
      {'status': 'present', 'envelope': 'synthetic', 'extra': true},
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => reply);
      await expectLater(NativeAuthSessionVault(project: 'project', channel: channel).read(), throwsStateError);
    }
  });

  test('invalid project never invokes native storage', () async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (_) async { calls++; return {'status': 'absent'}; });
    await expectLater(NativeAuthSessionVault(project: '../other', channel: channel).read(), throwsArgumentError);
    expect(calls, 0);
  });

  test('SDK saving and deletion remain explicitly unconnected', () async {
    final owner = AppAuthStorageOwner(vault: NativeAuthSessionVault(project: 'project', channel: channel),
      project: 'project', readLegacy: () async => null, logoutPending: () async => false);
    final adapter = NativeAuthSessionStorage(owner);
    await expectLater(adapter.initialize(), throwsStateError);
    await expectLater(adapter.hasAccessToken(), throwsStateError);
    await expectLater(adapter.accessToken(), throwsStateError);
    await expectLater(adapter.persistSession('synthetic'), throwsStateError);
    await expectLater(adapter.removePersistedSession(), throwsStateError);
  });
}

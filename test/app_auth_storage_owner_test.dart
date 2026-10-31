import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/auth/app_auth_storage_owner.dart';

class Vault implements AuthSessionVault {
  String? value;
  int writes = 0;
  int? failWrite;
  Completer<void>? pause;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String envelope) async {
    writes++;
    value = envelope;
    if (pause != null) await pause!.future;
    if (writes == failWrite) throw StateError('Synthetic lost reply.');
  }
}

void main() {
  test('copy preserves exact legacy bytes and committed restart never rereads legacy', () async {
    final vault = Vault();
    const legacy = '{"synthetic":"original bytes"}';
    var reads = 0;
    final owner = AppAuthStorageOwner(vault: vault, project: 'project',
      readLegacy: () async { reads++; return legacy; }, logoutPending: () async => false);
    expect((await owner.initialize()).phase, AuthStoragePhase.ready);
    expect(jsonDecode(vault.value!)['session'], legacy);
    final restarted = AppAuthStorageOwner(vault: vault, project: 'project',
      readLegacy: () async => throw StateError('must not fallback'), logoutPending: () async => false);
    expect((await restarted.initialize()).phase, AuthStoragePhase.ready);
    expect(reads, 1);
    expect(vault.writes, 2);
  });

  for (final failure in [1, 2]) {
    test('lost write reply $failure stays unknown and does not retry', () async {
      final vault = Vault()..failWrite = failure;
      final owner = AppAuthStorageOwner(vault: vault, project: 'project',
        readLegacy: () async => 'synthetic', logoutPending: () async => false);
      expect((await owner.initialize()).phase, AuthStoragePhase.unknown);
      expect((await owner.initialize()).phase, AuthStoragePhase.unknown);
      expect(vault.writes, failure);
      final restarted = AppAuthStorageOwner(vault: vault, project: 'project',
        readLegacy: () async => throw StateError('no fallback'), logoutPending: () async => false);
      expect((await restarted.initialize()).phase,
        failure == 1 ? AuthStoragePhase.pending : AuthStoragePhase.ready);
    });
  }

  test('synchronous retirement during stage never commits or exposes ready', () async {
    final vault = Vault()..pause = Completer<void>();
    final owner = AppAuthStorageOwner(vault: vault, project: 'project',
      readLegacy: () async => 'synthetic', logoutPending: () async => false);
    final pending = owner.initialize();
    while (vault.writes == 0) { await Future<void>.delayed(Duration.zero); }
    owner.retire();
    vault.pause!.complete();
    expect((await pending).phase, AuthStoragePhase.blocked);
    expect(vault.writes, 1);
  });

  test('pending logout does not access legacy or vault writes', () async {
    final vault = Vault();
    final owner = AppAuthStorageOwner(vault: vault, project: 'project',
      readLegacy: () async => throw StateError('no access'), logoutPending: () async => true);
    expect((await owner.initialize()).phase, AuthStoragePhase.blocked);
    expect(vault.writes, 0);
  });

  test('wrong project or malformed secure value never falls back to legacy', () async {
    for (final value in ['broken', jsonEncode({'schema': 1, 'project': 'other',
      'state': 'committed', 'session': 'synthetic'})]) {
      final vault = Vault()..value = value;
      final owner = AppAuthStorageOwner(vault: vault, project: 'project',
        readLegacy: () async => throw StateError('no fallback'), logoutPending: () async => false);
      expect((await owner.initialize()).phase, AuthStoragePhase.unknown);
      expect(vault.writes, 0);
    }
  });
}

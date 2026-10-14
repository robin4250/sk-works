import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/security/security_export_guard.dart';

void main() {
  test('fresh challenge precedes the server snapshot authorization', () async {
    final calls = <String>[];
    await authorizeSecurityExport(
      actor: 'master',
      isActive: () => true,
      currentActor: () => 'master',
      reauthenticate: () async { calls.add('challenge'); return true; },
      authorizeSnapshot: () async { calls.add('snapshot'); },
    );
    expect(calls, ['challenge', 'snapshot']);
  });

  test('cancelled challenge never reads or exports the snapshot', () async {
    var reads = 0;
    await expectLater(authorizeSecurityExport(
      actor: 'master',
      isActive: () => true,
      currentActor: () => 'master',
      reauthenticate: () async => false,
      authorizeSnapshot: () async { reads++; },
    ), throwsStateError);
    expect(reads, 0);
  });

  test('actor change during challenge blocks the snapshot read', () async {
    var actor = 'master';
    var reads = 0;
    await expectLater(authorizeSecurityExport(
      actor: 'master',
      isActive: () => true,
      currentActor: () => actor,
      reauthenticate: () async { actor = 'other'; return true; },
      authorizeSnapshot: () async { reads++; },
    ), throwsStateError);
    expect(reads, 0);
  });

  test('actor change during the server check blocks handoff', () async {
    var actor = 'master';
    await expectLater(authorizeSecurityExport(
      actor: 'master',
      isActive: () => true,
      currentActor: () => actor,
      reauthenticate: () async => true,
      authorizeSnapshot: () async { actor = 'other'; },
    ), throwsStateError);
  });

  test('server denial blocks handoff after successful local challenge', () async {
    await expectLater(authorizeSecurityExport(
      actor: 'master',
      isActive: () => true,
      currentActor: () => 'master',
      reauthenticate: () async => true,
      authorizeSnapshot: () async => throw StateError('denied'),
    ), throwsStateError);
  });

  for (final reason in ['background lock', 'authentication expiry']) {
    test('$reason during server authorization prevents file handoff', () async {
      var active = true;
      var handoffs = 0;
      Future<void> export() async {
        await authorizeSecurityExport(
          actor: 'master',
          currentActor: () => 'master',
          isActive: () => active,
          reauthenticate: () async => true,
          authorizeSnapshot: () async { active = false; },
        );
        handoffs++;
      }
      await expectLater(export(), throwsStateError);
      expect(handoffs, 0);
    });
  }

  test('already locked screen cannot start authentication or read', () async {
    var calls = 0;
    await expectLater(authorizeSecurityExport(
      actor: 'master',
      currentActor: () => 'master',
      isActive: () => false,
      reauthenticate: () async { calls++; return true; },
      authorizeSnapshot: () async { calls++; },
    ), throwsStateError);
    expect(calls, 0);
  });
}

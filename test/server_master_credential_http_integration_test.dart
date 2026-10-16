import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sk_works/features/settings/master_credential_repository.dart';
import 'package:sk_works/features/settings/master_password_entry_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// No mock responses. Only rewrite the SDK's fixed /rest/v1/rpc prefix to the
// disposable PostgREST service. Deny every other URL/path and all redirects.
class _FixtureRpcTransport extends http.BaseClient {
  _FixtureRpcTransport(this.base);
  final Uri base;
  final http.Client _inner = http.Client();
  final names = <String>[];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    const allowed = {
      'master_password_capability', 'current_master_password_status',
      'begin_master_password_operation', 'complete_master_password_operation',
      'read_master_password_request', 'verify_master_password_operation',
    };
    final uri = request.url;
    final name = uri.path.split('/').last;
    if (uri.scheme != 'http' || uri.host != '127.0.0.1' ||
        uri.port != base.port || uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty || uri.fragment.isNotEmpty ||
        uri.path != '/rest/v1/rpc/$name' ||
        request.method != 'POST' || !allowed.contains(name)) {
      throw StateError('Non-fixture request rejected');
    }
    names.add(name);
    final forwarded = http.Request('POST', base.replace(path: '/rpc/$name'))
      ..headers.addAll(request.headers)
      ..followRedirects = false
      ..bodyBytes = await request.finalize().toBytes();
    final response = await _inner.send(forwarded);
    if (response.statusCode >= 300 && response.statusCode < 400) {
      await response.stream.drain<void>();
      throw StateError('Fixture redirect rejected');
    }
    return response;
  }
  @override
  void close() { _inner.close(); super.close(); }
}

void main() {
  final file = Platform.environment['SKO_MASTER_CREDENTIAL_HTTP_FIXTURE'];
  test('product Master repositories reach actual isolated PostgreSQL and preserve identity', () async {
    if (file == null || file.isEmpty) {
      throw StateError('Dedicated fixture path required');
    }
    final fixture = jsonDecode(await File(file).readAsString()) as Map<String, dynamic>;
    final base = Uri.parse(fixture['base_url'] as String);
    if (base.scheme != 'http' || base.host != '127.0.0.1' ||
        base.userInfo.isNotEmpty || base.query.isNotEmpty || base.fragment.isNotEmpty) {
      throw StateError('Disposable loopback fixture only');
    }
    final transport = _FixtureRpcTransport(base);
    final client = SupabaseClient(base.origin, 'synthetic-unused-public-key',
      authOptions: AuthClientOptions(autoRefreshToken: false),
      httpClient: transport);
    addTearDown(() async { await client.dispose(); transport.close(); });
    await client.auth.setInitialSession(jsonEncode(fixture['session']));
    final repo = MasterCredentialRepository(client, deviceKey: fixture['device_key'] as String);
    final binding = repo.binding!;
    expect(binding.actor, fixture['actor']);
    expect(binding.sessionId, fixture['session_id']);
    final initial = await repo.read(binding);
    expect(initial.configured, isFalse); expect(initial.version, 0);
    MasterCredentialPending pending(String operation, int version) =>
      MasterCredentialPending(actor: binding.actor, sessionId: binding.sessionId,
        deviceFingerprint: binding.deviceFingerprint,
        requestId: newMasterCredentialRequestId(), operation: operation, version: version);
    const common = 'fixture-client-common-secondary-password';
    const first = 'fixture-client-initial-master-password';
    const next = 'fixture-client-new-master-password';
    final setup = pending('setup', 0);
    expect(await repo.receipt(binding, setup), MasterCredentialReceipt.pending);
    final setupChallenge = await repo.begin(binding, setup);
    expect(await repo.receipt(binding, setup), MasterCredentialReceipt.pending);
    await repo.commit(binding, setup, setupChallenge, verificationPassword: common, newPassword: first);
    expect(await repo.receipt(binding, setup), MasterCredentialReceipt.applied);
    expect((await repo.read(binding)).version, 1);
    final failed = pending('change', 1), failedChallenge = await repo.begin(binding, failed);
    await expectLater(repo.commit(binding, failed, failedChallenge,
      verificationPassword: common, newPassword: next),
      throwsA(isA<MasterCredentialRejected>().having((e) => e.status, 'status', 'not_verified')));
    expect(await repo.receipt(binding, failed), MasterCredentialReceipt.notApplied);
    final actualChange = pending('change', 1);
    final actualChallenge = await repo.begin(binding, actualChange);
    await repo.commit(binding, actualChange, actualChallenge, verificationPassword: first, newPassword: next);
    expect(await repo.receipt(binding, actualChange), MasterCredentialReceipt.applied);
    final entry = MasterPasswordEntryRepository(client, deviceKey: fixture['device_key'] as String);
    expect((await entry.read(binding)).version, 2);
    final rejectedRequest = newMasterCredentialRequestId();
    final rejectedChallenge = await entry.beginUnlock(binding, 2, rejectedRequest);
    await expectLater(entry.verifyUnlock(binding, 2, rejectedRequest, rejectedChallenge, common),
      throwsA(isA<MasterCredentialRejected>().having((e) => e.status, 'status', 'not_verified')));
    final unlockRequest = newMasterCredentialRequestId();
    final unlockChallenge = await entry.beginUnlock(binding, 2, unlockRequest);
    await entry.verifyUnlock(binding, 2, unlockRequest, unlockChallenge, next);
    expect(client.auth.currentUser!.id, fixture['actor']);
    expect(repo.binding!.sameAs(binding), isTrue);
    expect(transport.names.where((n) => n == 'complete_master_password_operation').length, 3);
    expect(transport.names.where((n) => n == 'verify_master_password_operation').length, 2);
  }, skip: file == null, timeout: const Timeout(Duration(minutes: 2)));
}

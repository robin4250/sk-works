import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/settings/master_credential_repository.dart';

const _actorA = '81000000-0000-0000-0000-000000000001';
const _actorB = '81000000-0000-0000-0000-000000000002';
const _sidA = '81000000-0000-0000-0000-000000000003';
const _sidB = '81000000-0000-0000-0000-000000000004';
const _sidNew = '81000000-0000-0000-0000-000000000005';
const _requestA = '81000000-0000-0000-0000-000000000006';
const _requestB = '81000000-0000-0000-0000-000000000007';
const _device = 'synthetic-journal-device-key-longer-than-32';
const _protocol = 'sko-master-password-v1';

Map<String, dynamic> _session(String actor, String sid) {
  String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return {
    'access_token': '${part({'alg': 'HS256'})}.${part({'sub': actor, 'session_id': sid, 'role': 'authenticated', 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.synthetic',
    'refresh_token': 'synthetic-$sid', 'token_type': 'bearer', 'expires_in': 3600,
    'user': {'id': actor, 'aud': 'authenticated', 'created_at': '2026-10-16T00:00:00Z', 'app_metadata': <String, dynamic>{}, 'user_metadata': <String, dynamic>{}},
  };
}
class _DelayedStorage extends GotrueAsyncStorage {
  final entered = Completer<void>(), release = Completer<void>();
  @override Future<String?> getItem({required String key}) async => null;
  @override Future<void> setItem({required String key, required String value}) async {}
  @override Future<void> removeItem({required String key}) async {
    if (!entered.isCompleted) entered.complete();
    await release.future;
  }
}
class _Fixture {
  _Fixture({GotrueAsyncStorage? storage}) {
    client = SupabaseClient('https://master-journal-logout-fixture.invalid', 'public_fixture',
      authOptions: AuthClientOptions(autoRefreshToken: false, pkceAsyncStorage: storage),
      httpClient: MockClient((request) async {
        expect(request.url.host, 'master-journal-logout-fixture.invalid');
        requests.add(request);
        final path = request.url.path;
        dynamic result;
        if (path == '/auth/v1/token') {
          final body = jsonDecode(request.body) as Map;
          final isA = body['phone'] == '+819012345678';
          result = _session(isA ? _actorA : _actorB, isA ? aSession : _sidB);
        } else if (path == '/auth/v1/logout') {
          result = <String, dynamic>{};
        } else if (path == '/rest/v1/rpc/complete_master_password_operation') {
          throw http.ClientException('Synthetic response lost after request dispatch');
        } else if (path == '/rest/v1/rpc/read_master_password_request') {
          final body = jsonDecode(request.body) as Map;
          result = {'protocol': _protocol, 'status': receiptStatus, 'request_id': body['p_request_id'],
            if (receiptStatus == 'found') 'result': {'protocol': _protocol, 'status': 'applied', 'operation': 'setup', 'request_id': body['p_request_id'], 'credential_version': 1, 'configured': true}};
        } else {
          throw StateError('Unexpected synthetic request');
        }
        return http.Response(jsonEncode(result), 200, headers: {'content-type': 'application/json'}, request: request);
      }));
    repository = MasterCredentialRepository(client, deviceKey: _device);
  }
  late final SupabaseClient client;
  late final MasterCredentialRepository repository;
  final requests = <http.Request>[];
  String aSession = _sidA, receiptStatus = 'not_found';
  Future<void> login({bool actorB = false}) async {
    await client.auth.signInWithPassword(phone: actorB ? '+819012345679' : '+819012345678', password: 'synthetic-password');
  }
  MasterCredentialPending pending(String requestId) {
    final b = repository.binding!;
    return MasterCredentialPending(actor: b.actor, sessionId: b.sessionId, deviceFingerprint: b.deviceFingerprint, requestId: requestId, operation: 'setup', version: 0);
  }
}
Future<Map<String, String?>> _snapshot() async {
  final prefs = await SharedPreferences.getInstance();
  return {for (final key in prefs.getKeys()) key: prefs.getString(key)};
}
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('late SDK signedOut carrying actor B leaves both captured A and current B journals intact', () async {
    final storage = _DelayedStorage();
    final w = _Fixture(storage: storage);
    final events = <AuthState>[];
    final subscription = w.client.auth.onAuthStateChange.listen(events.add);
    await w.login();
    final bindingA = w.repository.binding!, pendingA = w.pending(_requestA);
    await w.repository.remember(pendingA);
    final logout = w.client.auth.signOut(scope: SignOutScope.local);
    await storage.entered.future;
    expect(w.client.auth.currentSession, isNull);
    await w.login(actorB: true);
    final bindingB = w.repository.binding!, pendingB = w.pending(_requestB);
    await w.repository.remember(pendingB);
    final before = await _snapshot();
    expect(before.length, 2);
    storage.release.complete(); await logout; await Future<void>.delayed(Duration.zero);
    expect(events.any((event) => event.event == AuthChangeEvent.signedOut && event.session?.user.id == _actorB), isTrue);
    expect(w.client.auth.currentUser!.id, _actorB);
    expect(await _snapshot(), before);
    expect((await w.repository.pending(bindingA))!.requestId, _requestA);
    expect((await w.repository.pending(bindingB))!.requestId, _requestB);
    final sent = w.requests.singleWhere((r) => r.url.path == '/auth/v1/logout');
    expect(sent.headers['Authorization'], 'Bearer ${bindingA.token}');
    expect(sent.url.queryParameters['scope'], 'local');
    expect(w.requests.where((r) => r.url.path.startsWith('/rest/')), isEmpty);
    await subscription.cancel(); await w.client.dispose();
  });
  test('terminal A receipt permits exact A forget while B and replaced same-key metadata survive', () async {
    for (final terminal in ['found', 'not_applied']) {
      SharedPreferences.setMockInitialValues({});
      final w = _Fixture(); await w.login();
      final bindingA = w.repository.binding!, pendingA = w.pending(_requestA);
      await w.repository.remember(pendingA); w.receiptStatus = terminal;
      expect(await w.repository.receipt(bindingA, pendingA), terminal == 'found' ? MasterCredentialReceipt.applied : MasterCredentialReceipt.notApplied);
      await w.login(actorB: true);
      final bindingB = w.repository.binding!, pendingB = w.pending(_requestB);
      await w.repository.remember(pendingB);
      final before = await _snapshot();
      final keyA = before.keys.singleWhere((key) => key.endsWith(_requestA));
      final keyB = before.keys.singleWhere((key) => key.endsWith(_requestB));
      await w.repository.forget(pendingA);
      expect(await _snapshot(), {keyB: before[keyB]});
      expect((await w.repository.pending(bindingB))!.requestId, _requestB);
      // A stale exact-target cleanup cannot erase replacement metadata at its key.
      final prefs = await SharedPreferences.getInstance();
      final replacement = jsonEncode({...pendingA.toJson(), 'version': 1});
      await prefs.setString(keyA, replacement);
      await expectLater(w.repository.forget(pendingA), throwsStateError);
      expect(await _snapshot(), {keyA: replacement, keyB: before[keyB]});
      expect(w.requests.where((r) => r.url.path.endsWith('complete_master_password_operation')), isEmpty);
      await w.client.dispose();
    }
  });
  test('unknown commit survives logout and same actor new session without automatic clear or resend', () async {
    final w = _Fixture(); await w.login();
    final original = w.repository.binding!, pending = w.pending(_requestA);
    await w.repository.remember(pending);
    final challenge = MasterCredentialChallenge(id: '81000000-0000-0000-0000-000000000008', nonce: List.filled(64, 'a').join(), expiresAt: DateTime.now().toUtc().add(const Duration(seconds: 120)));
    await expectLater(w.repository.commit(original, pending, challenge, verificationPassword: 'synthetic-secondary', newPassword: 'synthetic-master'), throwsA(isA<http.ClientException>()));
    expect(await w.repository.receipt(original, pending), MasterCredentialReceipt.pending);
    final before = await _snapshot();
    await w.client.auth.signOut(scope: SignOutScope.local);
    w.aSession = _sidNew; await w.login();
    final fresh = MasterCredentialRepository(w.client, deviceKey: _device), current = fresh.binding!;
    expect(current.actor, original.actor); expect(current.sessionId, isNot(original.sessionId));
    expect(await fresh.pending(current), isNull);
    expect(await _snapshot(), before);
    await expectLater(fresh.receipt(current, pending), throwsA(isA<MasterCredentialRejected>()));
    expect(await _snapshot(), before);
    expect(w.requests.where((r) => r.url.path.endsWith('complete_master_password_operation')).length, 1);
    expect(w.requests.where((r) => r.url.path.endsWith('read_master_password_request')).length, 1);
    expect(w.requests.where((r) => r.url.path.endsWith('/signup') || r.url.path.endsWith('/user')), isEmpty);
    await w.client.dispose();
  });
}

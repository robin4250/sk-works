import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/auth/app_auth_mutation_gateway.dart';
import 'package:sk_works/features/shared/trade_document_form_session.dart';

const _actor = '10000000-0000-0000-0000-000000000001';
const _sidA = '20000000-0000-0000-0000-000000000001';
const _sidB = '20000000-0000-0000-0000-000000000002';

class _Wire extends http.BaseClient {
  _Wire() : expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
  final int expiry;
  String sid = _sidA;
  final requests = <http.BaseRequest>[];
  Completer<void>? holdLogout;
  Map<String, dynamic> get user => {
    'id': _actor, 'aud': 'authenticated', 'role': 'authenticated',
    'created_at': '2026-01-01T00:00:00Z', 'user_metadata': {'fixture': 'restored'},
  };
  String token(String value) {
    String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    return '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part({'sub': _actor, 'session_id': value, 'role': 'authenticated', 'exp': expiry})}.${base64Url.encode(List<int>.filled(32, 7)).replaceAll('=', '')}';
  }
  Map<String, dynamic> get session => {
    'access_token': token(sid), 'refresh_token': 'synthetic-refresh',
    'expires_in': 3600, 'expires_at': expiry, 'token_type': 'bearer', 'user': user,
  };
  Iterable<http.BaseRequest> get rpcs => requests.where((r) => r.url.path.contains('/rest/v1/rpc/'));
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    Object value;
    if (request.url.path.endsWith('/auth/v1/token')) {
      value = session;
    } else if (request.url.path.endsWith('/auth/v1/user') && request.method == 'PUT') {
      value = {...user, 'user_metadata': {'fixture': 'historical-update'}};
    } else if (request.url.path.endsWith('/auth/v1/logout')) {
      await holdLogout?.future;
      value = <String, dynamic>{};
    } else {
      expect(request.url.path, '/rest/v1/rpc/restored_session_probe');
      value = {'ok': true};
    }
    return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(value))), 200,
      headers: {'content-type': 'application/json'}, request: request);
  }
}

class _Fixture {
  final wire = _Wire();
  late final client = SupabaseClient('https://synthetic.invalid', 'synthetic-public',
    httpClient: wire, authOptions: const AuthClientOptions(autoRefreshToken: false));
  Future<void> initial() => client.auth.setInitialSession(jsonEncode(wire.session));
  Future<void> recover() async { await client.auth.recoverSession(jsonEncode(wire.session)); }
  Future<void> signIn([String sid = _sidA]) async {
    wire.sid = sid;
    await client.auth.signInWithPassword(email: 'synthetic@example.invalid', password: 'synthetic-password');
  }
  Future<void> close() async {
    if (wire.holdLogout?.isCompleted == false) wire.holdLogout!.complete();
    await client.dispose();
  }
}

Future<void> _drain() => Future<void>.delayed(Duration.zero);
Future<void> _probe(TradeDocumentFormSession scope, _Fixture fixture) async {
  await scope.ready();
  expect(await scope.rpc('restored_session_probe', const {}), {'ok': true});
  expect(fixture.wire.rpcs, hasLength(1));
  expect(fixture.wire.rpcs.single.headers['Authorization'] ?? fixture.wire.rpcs.single.headers['authorization'],
    'Bearer ${fixture.client.auth.currentSession!.accessToken}');
}

void main() {
  setUp(() => TestWidgetsFlutterBinding.ensureInitialized()
    .handleAppLifecycleStateChanged(AppLifecycleState.resumed));

  test('pinned SDK initial restoration silently replaces the session and replays cached state before a new live event', () async {
    final f = _Fixture(); addTearDown(f.close);
    await f.initial();
    final initial = f.client.auth.currentSession!;
    await f.recover();
    final recovered = f.client.auth.currentSession!;
    expect(identical(initial, recovered), isFalse);
    expect(recovered.toJson(), initial.toJson());
    expect(f.wire.requests, isEmpty, reason: 'Nonexpired recovery is a real SDK local path, not HTTP refresh');
    final events = <AuthState>[];
    final subscription = f.client.auth.onAuthStateChange.listen(events.add);
    addTearDown(subscription.cancel);
    // No timer or pump between subscribing and the next public SDK mutation.
    await f.initial();
    final live = f.client.auth.currentSession!;
    await _drain();
    expect(events, hasLength(2));
    expect(events.map((e) => e.event), everyElement(AuthChangeEvent.initialSession));
    expect(identical(events.first.session, initial), isTrue);
    expect(identical(events.last.session, live), isTrue);
    expect(identical(live, recovered), isFalse);
    expect(live.toJson(), recovered.toJson());
  });

  for (final gatewayBeforeRecovery in [true, false]) {
    test('stable restored session can open a new document with gatewayBeforeRecovery=$gatewayBeforeRecovery', () async {
      final f = _Fixture(); addTearDown(f.close);
      await f.initial();
      if (gatewayBeforeRecovery) AppAuthMutationGateway.forClient(f.client);
      await f.recover();
      final scope = TradeDocumentFormSession(f.client);
      addTearDown(scope.dispose);
      await _probe(scope, f);
    });
  }

  test('historical SDK userUpdated replay is baseline for a newly opened document', () async {
    final f = _Fixture(); addTearDown(f.close);
    await f.initial();
    await f.client.auth.updateUser(UserAttributes(data: {'fixture': 'historical-update'}));
    final scope = TradeDocumentFormSession(f.client); addTearDown(scope.dispose);
    await _probe(scope, f);
    expect(f.wire.requests.where((r) => r.url.path.endsWith('/auth/v1/user')), hasLength(1));
  });

  for (final restoreFirst in [false, true]) {
    test('immediate same UID SID and exact token fresh sign-in retires entry restoreFirst=$restoreFirst', () async {
      final f = _Fixture(); addTearDown(f.close);
      await f.initial(); if (restoreFirst) await f.recover();
      final captured = f.client.auth.currentSession!;
      final scope = TradeDocumentFormSession(f.client); addTearDown(scope.dispose);
      await f.signIn();
      expect(f.client.auth.currentSession!.accessToken, captured.accessToken);
      expect(f.client.auth.currentSession!.toJson(), captured.toJson());
      await expectLater(scope.ready(), throwsStateError);
      expect(f.wire.rpcs, isEmpty);
    });
  }

  test('immediate exact-value initial-session mutation is not laundered as cached restoration', () async {
    final f = _Fixture(); addTearDown(f.close); await f.initial(); await f.recover();
    final captured = f.client.auth.currentSession!;
    final scope = TradeDocumentFormSession(f.client); addTearDown(scope.dispose);
    await f.initial();
    expect(f.client.auth.currentSession!.toJson(), captured.toJson());
    await expectLater(scope.ready(), throwsStateError);
    expect(f.wire.rpcs, isEmpty);
  });

  test('a silent same-value recovery after entry is terminal rather than a new baseline', () async {
    final f = _Fixture(); addTearDown(f.close); await f.initial();
    final scope = TradeDocumentFormSession(f.client); addTearDown(scope.dispose);
    await scope.ready();
    final captured = f.client.auth.currentSession!;
    await f.recover();
    expect(f.client.auth.currentSession!.toJson(), captured.toJson());
    expect(identical(f.client.auth.currentSession, captured), isFalse);
    expect(scope.requireScope, throwsStateError);
    await expectLater(scope.ready(), throwsStateError);
    expect(f.wire.rpcs, isEmpty);
  });

  test('live public SDK user update after baseline is terminal even with the same token', () async {
    final f = _Fixture(); addTearDown(f.close); await f.initial(); await f.recover();
    final scope = TradeDocumentFormSession(f.client); addTearDown(scope.dispose);
    await scope.ready();
    final captured = f.client.auth.currentSession;
    await f.client.auth.updateUser(UserAttributes(data: {'fixture': 'historical-update'}));
    expect(f.client.auth.currentSession!.accessToken, captured!.accessToken);
    await _drain();
    expect(scope.requireScope, throwsStateError);
    expect(f.wire.rpcs, isEmpty);
  });

  test('same UID A B A sequence cannot revive an entered document', () async {
    final f = _Fixture(); addTearDown(f.close); await f.initial(); await f.recover();
    final scope = TradeDocumentFormSession(f.client); addTearDown(scope.dispose);
    await scope.ready();
    await f.signIn(_sidB); await f.signIn(_sidA);
    await expectLater(scope.ready(), throwsStateError);
    expect(f.wire.rpcs, isEmpty);
  });

  test('logout intent retires restored entry before SDK logout completes or any RPC', () async {
    final f = _Fixture(); addTearDown(f.close); await f.initial(); await f.recover();
    final scope = TradeDocumentFormSession(f.client); addTearDown(scope.dispose);
    await scope.ready();
    f.wire.holdLogout = Completer<void>();
    final logout = AppAuthMutationGateway.forClient(f.client).signOut();
    expect(scope.isCurrent, isFalse);
    await expectLater(scope.ready(), throwsStateError);
    expect(f.wire.rpcs, isEmpty);
    f.wire.holdLogout!.complete(); await logout;
  });
}

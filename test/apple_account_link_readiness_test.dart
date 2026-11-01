import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sk_works/features/auth/apple_account_link.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const actor = '30000000-0000-0000-0000-000000000001';
const other = '30000000-0000-0000-0000-000000000002';

Map<String, dynamic> user(String id, {bool google = true, bool apple = false}) => {
  'id': id, 'aud': 'authenticated', 'email': 'synthetic@example.invalid',
  'created_at': '2026-01-01T00:00:00Z', 'app_metadata': {}, 'user_metadata': {},
  'identities': [for (final provider in [if (google) 'google', if (apple) 'apple'])
    {'id': '$id-$provider', 'identity_id': id, 'user_id': id, 'provider': provider,
      'identity_data': {'sub': '$id-$provider'}, 'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z'}],
};

String session(String id, {int age = 0}) {
  String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return jsonEncode({'access_token': '${part({'alg':'HS256'})}.${part({
    'sub':id,'session_id':'synthetic-$id-$age','exp':now+3600,
    'amr':[{'method':'oauth','timestamp':now-age}]})}.synthetic',
    'refresh_token':'synthetic', 'token_type':'bearer', 'expires_in':3600, 'user':user(id)});
}

class ReadinessEventAppleLink extends AppleAccountLink {
  ReadinessEventAppleLink(super.client, this.events, {
    required Future<bool> Function() providerCheck,
  }) : super.forTesting(settingsUrl: Uri.parse('https://apple-readiness.invalid/auth/v1/settings'),
    publicKey: 'synthetic-public', providerCheck: providerCheck,
    launch: (_) async => throw StateError('readiness must never launch OAuth'));
  final Stream<AuthState> events;
  @override Stream<AuthState> get changes => events;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SupabaseClient client;
  late AppleAccountLink source;
  late MockClient network;
  late List<http.Request> requests;
  bool provider = true, failProvider = false, google = true, apple = false, member = true;
  String serverActor = actor;
  Completer<void>? holdProvider, reachedProvider;
  int launches = 0;

  setUp(() async {
    provider = true; failProvider = false; google = true; apple = false; member = true;
    serverActor = actor; holdProvider = null; reachedProvider = null; launches = 0; requests = [];
    network = MockClient((request) async {
      requests.add(request);
      final Object body;
      if (request.url.path.endsWith('/user')) {
        body = user(serverActor, google: google, apple: apple);
      } else if (request.url.path.endsWith('/company_members')) {
        body = member ? [{'company_id':'synthetic-company', 'role':'owner'}] : [];
      } else {
        throw StateError('unexpected fixture route');
      }
      return http.Response(jsonEncode(body), 200,
        headers: {'content-type':'application/json'}, request: request);
    });
    client = SupabaseClient('https://apple-readiness.invalid', 'synthetic-public',
      authOptions: const AuthClientOptions(autoRefreshToken: false), httpClient: network);
    await client.auth.setInitialSession(session(actor));
    source = AppleAccountLink.forTesting(client,
      settingsUrl: Uri.parse('https://apple-readiness.invalid/auth/v1/settings'),
      publicKey: 'synthetic-public', providerCheck: () async {
        reachedProvider?.complete(); await holdProvider?.future;
        if (failProvider) throw StateError('synthetic settings failure');
        return provider;
      }, launch: (_) async { launches++; return true; });
  });
  tearDown(() async {
    await source.dispose(); await client.dispose(); network.close();
  });

  void noAuthMutation(String token) {
    expect(client.auth.currentSession!.accessToken, token);
    expect(client.auth.currentUser!.id, actor);
    expect(requests.every((r) => r.method == 'GET'), true);
    expect(requests.any((r) => r.url.path.contains('/token') ||
      r.url.path.contains('/signup') || r.url.path.contains('/logout') ||
      r.url.path.contains('/authorize') || r.url.path.contains('/identities')), false);
    expect(launches, 0);
  }

  test('production provider and recent OAuth never release manual enrollment', () async {
    final product = AppleAccountLink(client,
      settingsUrl: Uri.parse('https://apple-readiness.invalid/auth/v1/settings'),
      publicKey: 'synthetic-public', providerCheck: () async => true,
      launch: (_) async { launches++; return true; });
    addTearDown(product.dispose);
    final token = client.auth.currentSession!.accessToken;
    expect(await product.readiness(), AppleLinkReadiness.enrollmentPreparing);
    noAuthMutation(token);
    requests.clear();
    await expectLater(product.begin(), throwsA(isA<StateError>()
      .having((e) => e.message, 'reason', 'apple_link_enrollment_preparing')));
    expect(requests, isEmpty);
    expect(product.pending, false);
    noAuthMutation(token);
  });

  test('production reads an existing Apple link without enabling a new one', () async {
    apple = true;
    final product = AppleAccountLink(client,
      settingsUrl: Uri.parse('https://apple-readiness.invalid/auth/v1/settings'),
      publicKey: 'synthetic-public', providerCheck: () async => true,
      launch: (_) async { launches++; return true; });
    addTearDown(product.dispose);
    final token = client.auth.currentSession!.accessToken;
    expect(await product.readiness(), AppleLinkReadiness.linked);
    expect(product.pending, false);
    noAuthMutation(token);
  });

  test('ready is a server-verified read only preflight, not completed linking', () async {
    final token = client.auth.currentSession!.accessToken;
    expect(await source.readiness(), AppleLinkReadiness.ready);
    expect(source.pending, false);
    expect(client.auth.currentUser!.identities!.any((i) => i.provider == 'apple'), false);
    expect(requests.where((r) => r.url.path.endsWith('/company_members')), hasLength(1));
    noAuthMutation(token);
  });

  test('old OAuth reports missing same-session proof without sign-in or link URL', () async {
    await client.auth.setInitialSession(session(actor, age: 600));
    final token = client.auth.currentSession!.accessToken;
    expect(await source.readiness(), AppleLinkReadiness.recentOAuthRequired);
    await expectLater(source.begin(), throwsA(isA<StateError>()
      .having((e) => e.message, 'reason', 'apple_link_recent_google_required')));
    expect(source.pending, false);
    noAuthMutation(token);
  });

  test('future OAuth AMR cannot pass readiness', () async {
    await client.auth.setInitialSession(session(actor, age: -600));
    final token = client.auth.currentSession!.accessToken;
    expect(await source.readiness(), AppleLinkReadiness.recentOAuthRequired);
    noAuthMutation(token);
  });

  test('disabled and unreadable provider remain distinct and recover', () async {
    final token = client.auth.currentSession!.accessToken;
    provider = false;
    expect(await source.providerStatus(), AppleLinkProviderStatus.disabled);
    expect(await source.readiness(), AppleLinkReadiness.providerDisabled);
    failProvider = true;
    expect(await source.providerStatus(), AppleLinkProviderStatus.unavailable);
    expect(await source.readiness(), AppleLinkReadiness.unavailable);
    failProvider = false; provider = true;
    expect(await source.readiness(), AppleLinkReadiness.ready);
    noAuthMutation(token);
  });

  test('wrong verified actor, missing Google or membership never enables linking', () async {
    final token = client.auth.currentSession!.accessToken;
    serverActor = other;
    expect(await source.readiness(), AppleLinkReadiness.unavailable);
    serverActor = actor; google = false;
    expect(await source.readiness(), AppleLinkReadiness.googleRequired);
    google = true; member = false;
    expect(await source.readiness(), AppleLinkReadiness.unavailable);
    noAuthMutation(token);
  });

  test('already linked is server identity evidence rather than available start', () async {
    final token = client.auth.currentSession!.accessToken;
    apple = true;
    expect(await source.readiness(), AppleLinkReadiness.linked);
    expect(source.pending, false);
    noAuthMutation(token);
  });

  test('actor change during provider read refuses old readiness without replacing new session', () async {
    holdProvider = Completer<void>(); reachedProvider = Completer<void>();
    final pending = source.readiness(); await reachedProvider!.future;
    await client.auth.setInitialSession(session(other));
    final newToken = client.auth.currentSession!.accessToken;
    holdProvider!.complete();
    expect(await pending, AppleLinkReadiness.unavailable);
    expect(client.auth.currentUser!.id, other);
    expect(client.auth.currentSession!.accessToken, newToken);
    expect(launches, 0);
    expect(requests.every((r) => r.method == 'GET'), true);
  });

  test('same actor token change also refuses old readiness', () async {
    holdProvider = Completer<void>(); reachedProvider = Completer<void>();
    final pending = source.readiness(); await reachedProvider!.future;
    await client.auth.setInitialSession(session(actor, age: 1));
    final newToken = client.auth.currentSession!.accessToken;
    holdProvider!.complete();
    expect(await pending, AppleLinkReadiness.unavailable);
    noAuthMutation(newToken);
  });

  test('historical other-actor auth event invalidates readiness after current actor returns', () async {
    final events = StreamController<AuthState>();
    addTearDown(events.close);
    holdProvider = Completer<void>(); reachedProvider = Completer<void>();
    source = ReadinessEventAppleLink(client, events.stream, providerCheck: () async {
      reachedProvider!.complete(); await holdProvider!.future; return true;
    });
    final original = client.auth.currentSession!;
    final pending = source.readiness(); await reachedProvider!.future;
    events.add(AuthState(AuthChangeEvent.signedIn,
      Session.fromJson(jsonDecode(session(other)) as Map<String, dynamic>)));
    events.add(AuthState(AuthChangeEvent.signedIn, original));
    await Future<void>.delayed(Duration.zero);
    holdProvider!.complete();
    expect(await pending, AppleLinkReadiness.unavailable);
    noAuthMutation(original.accessToken);
  });

  test('historical same-actor token change invalidates readiness after old token returns', () async {
    final events = StreamController<AuthState>();
    addTearDown(events.close);
    holdProvider = Completer<void>(); reachedProvider = Completer<void>();
    source = ReadinessEventAppleLink(client, events.stream, providerCheck: () async {
      reachedProvider!.complete(); await holdProvider!.future; return true;
    });
    final original = client.auth.currentSession!;
    final pending = source.readiness(); await reachedProvider!.future;
    events.add(AuthState(AuthChangeEvent.tokenRefreshed,
      Session.fromJson(jsonDecode(session(actor, age: 1)) as Map<String, dynamic>)));
    events.add(AuthState(AuthChangeEvent.signedIn, original));
    await Future<void>.delayed(Duration.zero);
    holdProvider!.complete();
    expect(await pending, AppleLinkReadiness.unavailable);
    noAuthMutation(original.accessToken);
  });
  test('closed auth tracking invalidates pending readiness without identity writes', () async {
    final events = StreamController<AuthState>();
    holdProvider = Completer<void>(); reachedProvider = Completer<void>();
    source = ReadinessEventAppleLink(client, events.stream, providerCheck: () async {
      reachedProvider!.complete(); await holdProvider!.future; return true;
    });
    final original = client.auth.currentSession!.accessToken;
    final pending = source.readiness();
    await reachedProvider!.future;
    await events.close();
    holdProvider!.complete();
    expect(await pending, AppleLinkReadiness.unavailable);
    noAuthMutation(original);
  });

}

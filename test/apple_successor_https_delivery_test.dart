import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/auth/apple_successor_client_preparation.dart';
import 'package:sk_works/features/auth/apple_successor_https_delivery.dart';

const actor = '40000000-0000-0000-0000-000000000001';
const requestId = '40000000-0000-0000-0000-000000000003';
const sid = '40000000-0000-0000-0000-000000000005';
const bearer = 'synthetic-owner-bearer';
Map<String, dynamic> envelope() => {'schema': 1, 'request_id': requestId,
  'user_id': actor, 'session_id': sid, 'token_type': 'bearer',
  'access_token': 'synthetic-access', 'refresh_token': 'synthetic-refresh'};

// TestWidgetsBinding's default network stub is intentionally bypassed only for
// this loopback fixture, while the normal TLS certificate verification remains.
class _NativeFixtureHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory certificates;
  late SecurityContext serverContext, clientContext;
  late HttpServer server;
  late Uri endpoint;
  late Future<void> Function(HttpRequest) handler;
  late int calls, creations;
  setUpAll(() async {
    certificates = await Directory.systemTemp.createTemp('sko-apple-delivery-fixture-');
    final result = await Process.run('openssl', ['req', '-x509', '-newkey', 'rsa:2048',
      '-nodes', '-days', '1', '-subj', '/CN=localhost', '-addext',
      'subjectAltName=DNS:localhost,IP:127.0.0.1', '-addext', 'extendedKeyUsage=serverAuth', '-keyout', '${certificates.path}/key.pem',
      '-out', '${certificates.path}/cert.pem']);
    expect(result.exitCode, 0, reason: 'generate isolated TLS fixture');
    serverContext = SecurityContext()
      ..useCertificateChain('${certificates.path}/cert.pem')
      ..usePrivateKey('${certificates.path}/key.pem');
    clientContext = SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificates('${certificates.path}/cert.pem');
  });
  tearDownAll(() async { await certificates.delete(recursive: true); });
  setUp(() async {
    calls = 0; creations = 0;
    handler = (request) async {
      await request.drain<void>();
      request.response.headers.contentType = ContentType.json;
      request.response.headers.set('cache-control', 'no-store, private');
      request.response.write(jsonEncode(envelope()));
      await request.response.close();
    };
    server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, serverContext);
    endpoint = Uri.parse('https://127.0.0.1:${server.port}/internal/apple/enrollment');
    server.listen((request) async {
      calls++;
      try { await handler(request); } catch (_) {
        // The timeout/size-limit cases deliberately close the client socket.
        try { await request.response.close(); } catch (_) {}
      }
    });
  });
  tearDown(() async { await server.close(force: true); });
  AppleSuccessorHttpsDelivery delivery({bool enabled = true, Uri? uri,
    Duration deadline = const Duration(seconds: 3)}) => AppleSuccessorHttpsDelivery(
      endpoint: uri ?? endpoint, enabled: enabled, deadline: deadline,
      clientFactory: () { creations++; return _NativeFixtureHttp().createHttpClient(clientContext); });
  Future<Map<String, dynamic>> receive(AppleSuccessorHttpsDelivery value) => value.receiveOnce(
    bearer: bearer, requestId: requestId, actor: actor, password: 'synthetic-password',
    idToken: 'synthetic-apple-id-token', rawNonce: 'N' * 43);

  test('default OFF and non-HTTPS configuration never create a client or send credentials', () async {
    await expectLater(receive(AppleSuccessorHttpsDelivery(endpoint: endpoint)), throwsStateError);
    for (final uri in [endpoint.replace(scheme: 'http'), endpoint.replace(query: 'untrusted=1'),
      endpoint.replace(userInfo: 'user:password'), endpoint.replace(fragment: 'other')]) {
      await expectLater(receive(delivery(uri: uri)), throwsStateError);
    }
    expect(calls, 0); expect(creations, 0);
  });
  test('one original TLS POST returns immutable bounded no-store envelope without retry', () async {
    handler = (request) async {
      expect(request.method, 'POST'); expect(request.uri.path, endpoint.path);
      expect(request.headers.value('authorization'), 'Bearer $bearer');
      expect(request.headers.value('x-sko-request-id'), requestId);
      expect(request.headers.value('accept-encoding'), 'identity');
      final input = jsonDecode(await utf8.decoder.bind(request).join());
      expect(input, {'password': 'synthetic-password', 'id_token': 'synthetic-apple-id-token', 'nonce': 'N' * 43});
      request.response.headers.contentType = ContentType.json;
      request.response.headers.set('cache-control', 'no-store, private');
      request.response.write(jsonEncode(envelope())); await request.response.close();
    };
    final value = delivery(), result = await receive(value);
    expect(result, envelope()); expect(() => result['user_id'] = 'other', throwsUnsupportedError);
    await expectLater(receive(value), throwsStateError);
    expect(calls, 1); expect(creations, 1);
  });
  test('303 redirect is never followed, including same-origin credentials endpoint', () async {
    handler = (request) async {
      await request.drain<void>();
      request.response.statusCode = HttpStatus.seeOther;
      request.response.headers.set('location', endpoint.resolve('/another').toString());
      await request.response.close();
    };
    final value = delivery();
    await expectLater(receive(value), throwsStateError);
    await expectLater(receive(value), throwsStateError);
    expect(calls, 1);
  });
  test('declared and chunked size limits reject before accepting credential data', () async {
    for (final declared in [true, false]) {
      handler = (request) async {
        await request.drain<void>();
        request.response.headers.contentType = ContentType.json;
        request.response.headers.set('cache-control', 'no-store');
        if (declared) { request.response.contentLength = AppleSuccessorHttpsDelivery.maxResponseBytes + 1; }
        request.response.add(List.filled(AppleSuccessorHttpsDelivery.maxResponseBytes + 1, 65));
        await request.response.close();
      };
      await expectLater(receive(delivery()), throwsStateError);
    }
    expect(calls, 2);
  });
  test('wrong request/actor, missing no-store, content encoding, and malformed UTF8 are rejected', () async {
    for (final variant in ['request', 'actor', 'cache', 'encoding', 'utf8']) {
      handler = (request) async {
        await request.drain<void>();
        request.response.headers.contentType = ContentType.json;
        if (variant != 'cache') { request.response.headers.set('cache-control', 'no-store'); }
        if (variant == 'encoding') { request.response.headers.set('content-encoding', 'gzip'); }
        final value = envelope();
        if (variant == 'request') { value['request_id'] = actor; }
        if (variant == 'actor') { value['user_id'] = requestId; }
        request.response.add(variant == 'utf8' ? [0xff, 0xff] : utf8.encode(jsonEncode(value)));
        await request.response.close();
      };
      await expectLater(receive(delivery()), throwsStateError);
    }
    expect(calls, 5);
  });
  test('whole-operation deadline closes stalled response and refuses late success/retry', () async {
    final started = Completer<void>(), closed = Completer<void>();
    handler = (request) async {
      await request.drain<void>();
      request.response.headers.contentType = ContentType.json;
      request.response.headers.set('cache-control', 'no-store');
      request.response.write('{'); await request.response.flush(); started.complete();
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      try {
        request.response.write(jsonEncode(envelope()).substring(1));
        await request.response.close();
      } finally { if (!closed.isCompleted) { closed.complete(); } }
    };
    final value = delivery(deadline: const Duration(milliseconds: 700));
    final result = expectLater(receive(value), throwsStateError);
    await result; expect(started.isCompleted, isTrue);
    await closed.future.timeout(const Duration(seconds: 3));
    await expectLater(receive(value), throwsStateError);
    expect(calls, 1);
  });
  const project = 'https://successor-fixture.invalid';
  const originalSid = '40000000-0000-0000-0000-000000000004';
  String sdkToken(String session) {
    String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    return '${part({'alg': 'HS256'})}.${part({'sub': actor, 'session_id': session,
      'exp': 4102444800, 'iss': '$project/auth/v1', 'aud': 'authenticated'})}.${base64Url.encode(List<int>.filled(32, 7)).replaceAll('=', '')}';
  }
  Map<String, dynamic> sdkUser({bool apple = false}) => {
    'id': actor, 'aud': 'authenticated', 'created_at': '2026-01-01T00:00:00Z',
    'app_metadata': <String, dynamic>{}, 'user_metadata': <String, dynamic>{},
    'identities': [
      {'id': 'google-$actor', 'identity_id': actor, 'user_id': actor, 'provider': 'google',
        'identity_data': {'sub': 'google-$actor'}, 'created_at': '2026-01-01T00:00:00Z', 'updated_at': '2026-01-01T00:00:00Z'},
      if (apple) {'id': 'apple-$actor', 'identity_id': requestId, 'user_id': actor, 'provider': 'apple',
        'identity_data': {'sub': 'synthetic-apple'}, 'created_at': '2026-01-01T00:00:00Z', 'updated_at': '2026-01-01T00:00:00Z'},
    ],
  };
  Future<({SupabaseClient application, AppleSuccessorClientPreparation preparation,
      StreamController<AuthState> events, List<String> paths})> sdkPreparation({bool actualHistory = false}) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() { debugDefaultTargetPlatformOverride = null; });
    final paths = <String>[], events = StreamController<AuthState>.broadcast();
    SupabaseClient sdk({bool apple = false}) => SupabaseClient(project, 'synthetic-public',
      authOptions: const AuthClientOptions(autoRefreshToken: false), httpClient: MockClient((request) async {
        paths.add('${apple ? "isolated" : "original"}:${request.url.path}');
        expect(request.method, 'GET', reason: 'no global mutation or refresh request');
        final result = request.url.path.endsWith('/user') ? sdkUser(apple: apple) : [{'company_id': requestId, 'role': 'owner'}];
        return http.Response(jsonEncode(result), 200, headers: {'content-type': 'application/json'}, request: request);
      }));
    final application = sdk();
    await application.auth.setInitialSession(jsonEncode({'access_token': sdkToken(originalSid),
      'refresh_token': 'synthetic-original-refresh', 'token_type': 'bearer', 'expires_in': 3600, 'user': sdkUser()}));
    final preparation = AppleSuccessorClientPreparation(application, projectUrl: project,
      publicKey: 'synthetic-public', enabled: true, authChanges: actualHistory ? null : events.stream,
      isolatedClientFactory: () => sdk(apple: true));
    addTearDown(() async { await preparation.dispose(); await events.close(); await application.dispose(); });
    return (application: application, preparation: preparation, events: events, paths: paths);
  }
  Future<void> prepare(AppleSuccessorClientPreparation preparation, AppleSuccessorHttpsDelivery value) =>
    preparation.prepareFromHttps(requestId: requestId, delivery: value,
      password: 'synthetic-password', idToken: 'synthetic-apple-id-token', rawNonce: 'N' * 43);
  test('original TLS response composes with isolated SDK preparation and never adopts application Auth', () async {
    final fixture = await sdkPreparation(actualHistory: true);
    final actualEvents = <String>[];
    final subscription = fixture.application.auth.onAuthStateChange.listen((state) {
      actualEvents.add('${state.event.name}:sameActor=${state.session?.user.id == actor}:sameToken=${state.session?.accessToken == sdkToken(originalSid)}');
    });
    addTearDown(subscription.cancel);
    // Drain and describe the pinned SDK ReplaySubject baseline before this
    // real-history composition. Diagnostics contain only event types/bools.
    await Future<void>.delayed(Duration.zero);
    handler = (request) async {
      expect(request.headers.value('authorization'), 'Bearer ${sdkToken(originalSid)}');
      await request.drain<void>();
      request.response.headers.contentType = ContentType.json;
      request.response.headers.set('cache-control', 'no-store');
      request.response.write(jsonEncode({...envelope(), 'access_token': sdkToken(sid)}));
      await request.response.close();
    };
    try { await prepare(fixture.preparation, delivery()); }
    catch (_) { fail('HTTPS/SDK composition failed at safe fixture stages: ${fixture.paths}, TLS calls=$calls, Auth history=$actualEvents'); }
    expect(fixture.preparation.ready, isTrue); expect(calls, 1);
    expect(fixture.application.auth.currentSession!.accessToken, sdkToken(originalSid));
    expect(fixture.application.auth.currentSession!.refreshToken, 'synthetic-original-refresh');
  });
  test('cancellation before send cannot create a client or retry', () async {
    final value = delivery()..cancel();
    await expectLater(receive(value), throwsStateError);
    expect(calls, 0); expect(creations, 0);
  });
  for (final phase in ['headers', 'body']) {
    for (final cause in ['dispose', 'background', 'auth', 'overlap']) {
      test('$cause cancellation closes stalled $phase without waiting for deadline or allowing retry', () async {
        final fixture = await sdkPreparation();
        final started = Completer<void>(), release = Completer<void>(), finished = Completer<void>();
        addTearDown(() { if (!release.isCompleted) { release.complete(); } });
        handler = (request) async {
          try {
            await request.drain<void>();
            request.response.headers.contentType = ContentType.json;
            request.response.headers.set('cache-control', 'no-store');
            if (phase == 'body') { request.response.write('{'); await request.response.flush(); }
            started.complete(); await release.future;
            final lateBody = jsonEncode({...envelope(), 'access_token': sdkToken(sid)});
            request.response.write(phase == 'body' ? lateBody.substring(1) : lateBody);
            await request.response.close();
          } finally { if (!finished.isCompleted) { finished.complete(); } }
        };
        final value = delivery(deadline: const Duration(seconds: 20));
        final result = expectLater(prepare(fixture.preparation, value), throwsStateError);
        await started.future.timeout(const Duration(seconds: 3));
        switch (cause) {
          case 'dispose': await fixture.preparation.dispose();
          case 'background': fixture.preparation.didChangeAppLifecycleState(AppLifecycleState.paused);
          case 'auth': fixture.events.add(const AuthState(AuthChangeEvent.signedOut, null));
          case 'overlap':
            await expectLater(prepare(fixture.preparation, value), throwsStateError);
            fixture.preparation.invalidate();
        }
        // This completes before the response is released and far before the
        // delivery deadline: invalidation must abort the actual owned socket.
        await result.timeout(const Duration(seconds: 2));
        expect(fixture.preparation.ready, isFalse);
        await expectLater(receive(value), throwsStateError);
        expect(calls, 1);
        expect(fixture.application.auth.currentSession!.accessToken, sdkToken(originalSid));
        release.complete(); await finished.future.timeout(const Duration(seconds: 3));
      });
    }
  }
  test('network error content never escapes the generic delivery error', () async {
    final value = AppleSuccessorHttpsDelivery(endpoint: endpoint, enabled: true,
      clientFactory: () => throw StateError('synthetic-password-and-refresh-secret'));
    try { await receive(value); fail('expected failure'); }
    catch (error) { expect(error.toString(), isNot(contains('synthetic-password-and-refresh-secret'))); }
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/auth/secondary_password_primary_verifier.dart';

User _user(String id, {String? phone = '+15550000001', String? email}) => User(
  id: id,
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: '2026-01-01T00:00:00Z',
  phone: phone,
  email: email,
);

Map<String, dynamic> _session(User user, {String sessionId = 'global-session', int expiresAt = 4102444800}) => {
  'access_token':
      '${base64Url.encode(utf8.encode('{}'))}.${base64Url.encode(utf8.encode(jsonEncode({'exp': expiresAt, 'sub': user.id, 'session_id': sessionId, 'role': 'authenticated'})))}.test',
  'refresh_token': 'temporary-test-token',
  'token_type': 'bearer',
  'expires_in': 3600,
  'user': user.toJson(),
};

class _Client extends GoTrueClient {
  _Client(String url) : super(url: url, autoRefreshToken: false);
  bool disposed = false;
  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

void main() {
  test(
    'delayed verification cannot replace a newly selected global actor session',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final received = Completer<void>();
      final release = Completer<void>();
      final requests = <Uri>[];
      final original = _user('original');
      Map<String, dynamic>? submitted;
      server.listen((request) async {
        requests.add(request.uri);
        if (request.uri.path.endsWith('/token')) {
          submitted =
              jsonDecode(await utf8.decoder.bind(request).join())
                  as Map<String, dynamic>;
          received.complete();
          await release.future;
          request.response.write(jsonEncode(_session(original, sessionId: 'temporary-session')));
        } else {
          request.response.write('{}');
        }
        await request.response.close();
      });
      final url = 'http://127.0.0.1:${server.port}/auth/v1';
      final shared = _Client(url);
      addTearDown(shared.dispose);
      await shared.setInitialSession(jsonEncode(_session(original)));
      final temporary = _Client(url);
      final verifier = SecondaryPasswordPrimaryVerifier(
        currentUser: () => shared.currentUser,
        currentSession: () => shared.currentSession,
        authChanges: shared.onAuthStateChange,
        createClient: () => temporary,
      );
      final result = verifier.verify('synthetic-password', captchaToken: 'synthetic-challenge');
      await received.future;
      await shared.setInitialSession(jsonEncode(_session(_user('new-actor'))));
      final newSession = shared.currentSession;
      release.complete();
      expect(await result, isFalse);
      expect(identical(shared.currentSession, newSession), isTrue);
      expect(shared.currentUser!.id, 'new-actor');
      expect(submitted!['gotrue_meta_security'], {'captcha_token': 'synthetic-challenge'});
      expect(submitted!['phone'], original.phone);
      expect(submitted!['email'], isNull);
      expect(requests.last.path, '/auth/v1/logout');
      expect(requests.last.queryParameters['scope'], 'local');
      expect(temporary.currentSession, isNull);
      expect(temporary.disposed, isTrue);
      expect(shared.disposed, isFalse);
    },
  );

  test(
    'email fallback succeeds with local cleanup and leaves shared session unchanged',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final actor = _user(
        'original',
        phone: null,
        email: 'synthetic@example.test',
      );
      final submitted = <String, dynamic>{};
      server.listen((request) async {
        if (request.uri.path.endsWith('/token')) {
          submitted.addAll(
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>,
          );
          request.response.write(jsonEncode(_session(actor, sessionId: 'temporary-session')));
        } else {
          request.response.write('{}');
        }
        await request.response.close();
      });
      final url = 'http://127.0.0.1:${server.port}/auth/v1';
      final shared = _Client(url);
      addTearDown(shared.dispose);
      await shared.setInitialSession(jsonEncode(_session(actor)));
      final before = shared.currentSession;
      final temporary = _Client(url);
      expect(
        await SecondaryPasswordPrimaryVerifier(
          currentUser: () => shared.currentUser,
        currentSession: () => shared.currentSession,
        authChanges: shared.onAuthStateChange,
          createClient: () => temporary,
        ).verify('synthetic-password'),
        isTrue,
      );
      expect(identical(shared.currentSession, before), isTrue);
      expect(submitted['email'], actor.email);
      expect(submitted['phone'], isNull);
      expect(temporary.currentSession, isNull);
      expect(temporary.disposed, isTrue);
    },
  );

  test(
    'rejected password still disposes isolated client without signing out global actor',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response.statusCode = 400;
        request.response.write(
          jsonEncode({
            'error_code': 'invalid_credentials',
            'msg': 'synthetic rejection',
          }),
        );
        await request.response.close();
      });
      final actor = _user('original');
      final temporary = _Client('http://127.0.0.1:${server.port}/auth/v1');
      await expectLater(
        SecondaryPasswordPrimaryVerifier(
          currentUser: () => actor,
          currentSession: () => Session.fromJson(_session(actor)),
          authChanges: const Stream<AuthState>.empty(),
          createClient: () => temporary,
        ).verify('synthetic-password'),
        throwsA(isA<AuthException>()),
      );
      expect(temporary.currentSession, isNull);
      expect(temporary.disposed, isTrue);
      expect(actor.id, 'original');
    },
  );
  for (final mode in ['A-B-A', 'A-new-session', 'same-session-refresh']) {
    test('temporary password verification is bound to auth history: $mode', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final received = Completer<void>(), release = Completer<void>();
      final requests = <Uri>[];
      final actor = _user('original');
      server.listen((request) async {
        requests.add(request.uri);
        if (request.uri.path.endsWith('/token')) {
          await utf8.decoder.bind(request).join();
          received.complete();
          await release.future;
          request.response.write(jsonEncode(_session(actor, sessionId: 'temporary-session')));
        } else { request.response.write('{}'); }
        await request.response.close();
      });
      final url = 'http://127.0.0.1:${server.port}/auth/v1';
      final shared = _Client(url);
      addTearDown(shared.dispose);
      await shared.setInitialSession(jsonEncode(_session(actor)));
      final originalToken = shared.currentSession!.accessToken;
      final temporary = _Client(url);
      final pending = SecondaryPasswordPrimaryVerifier(currentUser: () => shared.currentUser,
        currentSession: () => shared.currentSession, authChanges: shared.onAuthStateChange,
        createClient: () => temporary).verify('synthetic-password');
      await received.future;
      if (mode == 'A-B-A') {
        await shared.setInitialSession(jsonEncode(_session(_user('other'))));
        await shared.setInitialSession(jsonEncode(_session(actor)));
        expect(shared.currentSession!.accessToken, originalToken);
      } else if (mode == 'A-new-session') {
        await shared.setInitialSession(jsonEncode(_session(actor, sessionId: 'new-session')));
      } else {
        await shared.setInitialSession(jsonEncode(_session(actor, expiresAt: 4102444700)));
        expect(shared.currentSession!.accessToken, isNot(originalToken));
      }
      final current = shared.currentSession;
      release.complete();
      expect(await pending, mode == 'same-session-refresh');
      expect(identical(shared.currentSession, current), isTrue);
      expect(requests.last.path, '/auth/v1/logout');
      expect(requests.last.queryParameters['scope'], 'local');
      expect(temporary.currentSession, isNull);
      expect(temporary.disposed, isTrue);
    });
  }

  test('unexpected reuse of original session is refused without logout', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final actor = _user('original');
    final requests = <Uri>[];
    server.listen((request) async {
      requests.add(request.uri);
      await utf8.decoder.bind(request).join();
      request.response.write(jsonEncode(_session(actor)));
      await request.response.close();
    });
    final url = 'http://127.0.0.1:${server.port}/auth/v1';
    final shared = _Client(url);addTearDown(shared.dispose);
    await shared.setInitialSession(jsonEncode(_session(actor)));
    final original = shared.currentSession;
    final temporary = _Client(url);
    expect(await SecondaryPasswordPrimaryVerifier(currentUser: () => shared.currentUser,
      currentSession: () => shared.currentSession, authChanges: shared.onAuthStateChange,
      createClient: () => temporary).verify('synthetic-password'), isFalse);
    expect(requests.where((r) => r.path.endsWith('/logout')), isEmpty);
    expect(identical(shared.currentSession, original), isTrue);
    expect(temporary.disposed, isTrue);
  });

}


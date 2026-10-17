import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/auth/panel_seven_repository.dart';

Map<String, dynamic> user(String id) => {
  'id': id, 'aud': 'authenticated', 'created_at': '2026-01-01T00:00:00Z',
  'app_metadata': {'provider': 'google'},
  'email': 'owner@example.test',
  'email_confirmed_at': '2026-01-01T00:00:00Z',
  'identities': [
    {'id': id, 'identity_id': id, 'user_id': id, 'provider': 'google',
     'identity_data': {'sub': id}, 'created_at': '2026-01-01T00:00:00Z',
     'updated_at': '2026-01-01T00:00:00Z'},
  ],
};
String session(String id) => jsonEncode({
  'access_token': '${base64Url.encode(utf8.encode("{}"))}.${base64Url.encode(utf8.encode(jsonEncode({
    "sub": id, "exp": 4102444800, "amr": [{"method": "oauth"}],
  })))}.synthetic',
  'refresh_token': 'synthetic-refresh', 'token_type': 'bearer',
  'expires_in': 3600, 'user': user(id),
});


void main() {
  setUp(() => SharedPreferences.setMockInitialValues({
    'sko_secondary_biometric_enabled_a': true,
    'sko_secondary_biometric_enabled_b': false,
  }));
  test('reads original JWT and own providers without mutation or signup', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final paths = <String>[];
    final headers = <String?>[];
    server.listen((request) async {
      paths.add('${request.method} ${request.uri.path}');
      headers.add(request.headers.value('Authorization'));
      request.response.headers.contentType = ContentType.json;
      request.response.write(request.uri.path.endsWith('/user')
          ? jsonEncode(user('a')) : 'true');
      await request.response.close();
    });
    final client = SupabaseClient('http://127.0.0.1:${server.port}', 'synthetic',
        authOptions: const AuthClientOptions(autoRefreshToken: false));
    addTearDown(client.dispose);
    await client.auth.setInitialSession(session('a'));
    final token = client.auth.currentSession!.accessToken;
    final before = client.auth.currentSession;
    final repository = PanelSevenRepository(client,
        biometricAvailability: () async => true);
    final value = await repository.load();
    expect(value.providers, ['google']);
    expect(value.biometricEnabled, isTrue);
    expect(value.biometricAvailable, isTrue);
    expect(value.phone, isNull);
    expect(value.secondaryConfigured, isTrue);
    expect(value.sessionMethods, ['oauth']);
    expect(repository.isCurrent(value), isTrue);
    expect(paths, ['GET /auth/v1/user',
      'POST /rest/v1/rpc/secondary_password_configured']);
    expect(headers, everyElement('Bearer $token'));
    expect(identical(client.auth.currentSession, before), isTrue);
  });

  test('actor changes while getUser is pending reject response', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final received = Completer<void>();
    final release = Completer<void>();
    final paths = <String>[];
    server.listen((request) async {
      paths.add(request.uri.path);
      received.complete();
      await release.future;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(user('a')));
      await request.response.close();
    });
    final client = SupabaseClient('http://127.0.0.1:${server.port}', 'synthetic',
        authOptions: const AuthClientOptions(autoRefreshToken: false));
    addTearDown(client.dispose);
    await client.auth.setInitialSession(session('a'));
    final pending = PanelSevenRepository(client).load();
    final check = expectLater(pending, throwsStateError);
    try {
      await received.future.timeout(const Duration(seconds: 5));
      await client.auth.setInitialSession(session('b'));
    } finally {
      if (!release.isCompleted) release.complete();
    }
    await check;
    expect(client.auth.currentUser!.id, 'b');
    expect(paths, ['/auth/v1/user']);
  });

  test('secondary status failure is unknown, never unconfigured', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path.endsWith('/user')) {
        request.response.write(jsonEncode(user('a')));
      } else {
        request.response.statusCode = 403;
        request.response.write('{"code":"42501","message":"denied"}');
      }
      await request.response.close();
    });
    final client = SupabaseClient('http://127.0.0.1:${server.port}', 'synthetic',
        authOptions: const AuthClientOptions(autoRefreshToken: false));
    addTearDown(client.dispose);
    await client.auth.setInitialSession(session('a'));
    expect((await PanelSevenRepository(client).load()).secondaryConfigured,
        isNull);
  });

}

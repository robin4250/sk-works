import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _actor = '30000000-0000-0000-0000-000000000001';
const _other = '30000000-0000-0000-0000-000000000002';
const _host = 'identity-link-fixture.invalid';
const _redirect = 'com.skworks.sko://login-callback/';
class _Storage extends GotrueAsyncStorage {
  final values = <String, String>{};
  @override Future<String?> getItem({required String key}) async => values[key];
  @override Future<void> setItem({required String key, required String value}) async { values[key] = value; }
  @override Future<void> removeItem({required String key}) async { values.remove(key); }
}
Map<String, dynamic> _user(String id) => {
  'id': id, 'aud': 'authenticated', 'created_at': '2026-10-16T00:00:00Z',
  'app_metadata': {'provider': 'google', 'providers': ['google']},
  'user_metadata': <String, dynamic>{},
};
Map<String, dynamic> _session(String id) {
  String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return {'access_token': '${part({'alg': 'HS256'})}.${part({'sub': id, 'role': 'authenticated', 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.synthetic',
    'refresh_token': 'synthetic-$id', 'token_type': 'bearer', 'expires_in': 3600, 'user': _user(id)};
}
void main() {
  test('pinned authenticated identity authorize uses original JWT, Apple, exact callback and PKCE; URL is not linked success', () async {
    final storage = _Storage();
    final requests = <http.Request>[];
    final client = SupabaseClient('https://$_host', 'public_fixture',
      authOptions: AuthClientOptions(autoRefreshToken: false, pkceAsyncStorage: storage),
      httpClient: MockClient((r) async {
        expect(r.url.host, _host); requests.add(r);
        if (r.url.path == '/auth/v1/token') return http.Response(jsonEncode(_session(_actor)), 200, request: r);
        if (r.url.path == '/auth/v1/user') return http.Response(jsonEncode(_user(_actor)), 200, request: r);
        if (r.url.path == '/auth/v1/user/identities/authorize') return http.Response(jsonEncode({'url': 'https://apple-fixture.invalid/authorize'}), 200, request: r);
        throw StateError('Unexpected synthetic request');
      }));
    await client.auth.signInWithPassword(email: 'fixture@example.invalid', password: 'synthetic-password');
    final captured = client.auth.currentSession!;
    expect((await client.auth.getUser(captured.accessToken)).user!.id, _actor);
    final response = await client.auth.getLinkIdentityUrl(OAuthProvider.apple, redirectTo: _redirect);
    final request = requests.singleWhere((r) => r.url.path.endsWith('/identities/authorize'));
    expect(request.method, 'GET');
    expect(request.headers['Authorization'], 'Bearer ${captured.accessToken}');
    expect(request.url.queryParameters['provider'], 'apple');
    expect(request.url.queryParameters['redirect_to'], _redirect);
    expect(request.url.queryParameters['code_challenge_method'], 's256');
    expect(request.url.queryParameters['code_challenge'], isNotEmpty);
    expect(storage.values.values.any((v) => v.isNotEmpty), isTrue);
    expect(response.url, 'https://apple-fixture.invalid/authorize');
    // No callback was performed: obtaining an authorization URL is not success.
    expect(client.auth.currentUser!.id, _actor);
    expect(client.auth.currentUser!.appMetadata['providers'], ['google']);
    expect(requests.where((r) => r.url.path.endsWith('/signup') || r.method != 'GET' && r.url.path.endsWith('/user')), isEmpty);
    await client.dispose();
  });

  test('pinned server collision fails without signup, unlink, password update or UID replacement', () async {
    final requests = <http.Request>[];
    final client = SupabaseClient('https://$_host', 'public_fixture',
      authOptions: AuthClientOptions(autoRefreshToken: false, pkceAsyncStorage: _Storage()),
      httpClient: MockClient((r) async {
        expect(r.url.host, _host); requests.add(r);
        if (r.url.path == '/auth/v1/token') return http.Response(jsonEncode(_session(_actor)), 200, request: r);
        if (r.url.path.endsWith('/identities/authorize')) return http.Response(jsonEncode({'code': 'identity_already_exists', 'msg': 'Synthetic identity collision'}), 422, request: r);
        throw StateError('Unexpected synthetic request');
      }));
    await client.auth.signInWithPassword(email: 'fixture@example.invalid', password: 'synthetic-password');
    await expectLater(client.auth.getLinkIdentityUrl(OAuthProvider.apple, redirectTo: _redirect), throwsA(isA<AuthException>()));
    expect(client.auth.currentUser!.id, _actor);
    expect(requests.length, 2);
    expect(requests.any((r) => r.method == 'DELETE' || r.method == 'PUT' || r.url.path.endsWith('/signup')), isFalse);
    await client.dispose();
  });

  test('pinned getUser(captured JWT) does not pin global actor after another session arrives', () async {
    late String capturedToken;
    final client = SupabaseClient('https://$_host', 'public_fixture',
      authOptions: AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((r) async {
        expect(r.url.host, _host);
        if (r.url.path == '/auth/v1/token') {
          final id = (jsonDecode(r.body) as Map)['email'] == 'other@example.invalid' ? _other : _actor;
          return http.Response(jsonEncode(_session(id)), 200, request: r);
        }
        if (r.url.path == '/auth/v1/user') {
          expect(r.headers['Authorization'], 'Bearer $capturedToken');
          return http.Response(jsonEncode(_user(_actor)), 200, request: r);
        }
        throw StateError('Unexpected synthetic request');
      }));
    await client.auth.signInWithPassword(email: 'fixture@example.invalid', password: 'synthetic-password');
    final captured = client.auth.currentSession!;
    capturedToken = captured.accessToken;
    await client.auth.signInWithPassword(email: 'other@example.invalid', password: 'synthetic-password');
    expect((await client.auth.getUser(captured.accessToken)).user!.id, _actor);
    expect(client.auth.currentUser!.id, _other);
    // A future product action must compare its actor/generation after every await.
    // getUser success alone cannot authorize a late UI result for actor A.
    await client.dispose();
  });
}

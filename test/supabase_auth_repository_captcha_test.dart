import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sk_works/data/contracts.dart';
import 'package:sk_works/data/supabase_auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('email repository forwards each attempt token without reusing it', () async {
    final requests = <http.Request>[];
    final client = SupabaseClient('https://captcha.fixture.invalid', 'public-fixture',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response('{"error":"invalid_grant","error_description":"Invalid credentials"}', 400,
          headers: {'content-type': 'application/json'});
      }));
    addTearDown(client.dispose);
    final repository = SupabaseAuthRepository(client);
    for (final token in ['first-challenge', 'second-challenge']) {
      await expectLater(repository.signIn(email: 'fixture@example.invalid',
        password: 'synthetic-password', captchaToken: token), throwsA(isA<AuthException>()));
    }
    // Existing AuthRepository callers keep their original signature and do not
    // inherit the previous attempt's challenge.
    final AuthRepository legacy = repository;
    await expectLater(legacy.signIn(email: 'fixture@example.invalid',
      password: 'synthetic-password'), throwsA(isA<AuthException>()));
    expect(requests, hasLength(3));
    for (var i = 0; i < requests.length; i++) {
      final request = requests[i];
      expect(request.url.path, '/auth/v1/token');
      expect(request.url.queryParameters['grant_type'], 'password');
      final body = jsonDecode(request.body) as Map;
      expect(body['email'], 'fixture@example.invalid');
      expect(body['password'], 'synthetic-password');
      expect((body['gotrue_meta_security'] as Map?)?['captcha_token'],
        i < 2 ? ['first-challenge', 'second-challenge'][i] : isNull);
    }
    expect(client.auth.currentSession, isNull);
  });
}

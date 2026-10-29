import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/auth/secure_onboarding_repository.dart';

void main() {
  const id = '20000000-0000-0000-0000-000000000001';
  final user = {
    'id': id,
    'aud': 'authenticated',
    'created_at': '2026-10-19T00:00:00Z',
    'app_metadata': {},
    'user_metadata': {},
  };
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final token =
      '${part({'alg': 'HS256'})}.${part({'sub': id, 'session_id':'20000000-0000-0000-0000-000000000099', 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.synthetic';
  for (final status in [
    'missing_session',
    'state_error',
    'network_error',
    'switch_session',
    'switch_after_password',
    'switch_during_marker',
    'aba_preflight',
    'aba_password',
    'aba_marker',
    'missing',
    'malformed',
    'cancelled',
    'expired',
    'invalid',
    'empty',
    'approval_pending',
    'valid',
    'profile_pending',
  ]) {
    test('initial password preflight: $status', () async {
      final calls = <String>[];
      final state = {
        'invite_id': status == 'empty' ? '' : 'synthetic',
        'status':
            [
              'expired', 'invalid', 'valid', 'switch_session',
              'switch_after_password', 'switch_during_marker',
              'aba_preflight', 'aba_password', 'aba_marker',
            ].contains(status)
            ? 'invited'
            : status,
        'expires_at': status == 'invalid'
            ? 'invalid'
            : status == 'expired'
            ? '2020-01-01T00:00:00Z'
            : DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
      };
      late final SupabaseClient client;
      client = SupabaseClient(
        'https://fixture.invalid',
        'public-fixture',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((r) async {
          calls.add(r.url.path);
          Object? response;
          if (r.url.path == '/auth/v1/token') {
            response = {
              'access_token': token,
              'refresh_token': 'synthetic',
              'token_type': 'bearer',
              'expires_in': 3600,
              'user': user,
            };
          } else if (r.url.path == '/rest/v1/rpc/employee_onboarding_state') {
            if (status == 'network_error') {
              throw http.ClientException('synthetic disconnected');
            }
            if (status == 'state_error') {
              return http.Response(
                '{"message":"synthetic unavailable","code":"42501"}',
                403,
                headers: {'content-type': 'application/json'},
                request: r,
              );
            }
            if (status == 'switch_session') {
              await client.auth.signOut(scope: SignOutScope.local);
            }
            if (status == 'aba_preflight') {
              await client.auth.signOut(scope: SignOutScope.local);
              await client.auth.signInWithPassword(email: 'synthetic@example.invalid', password: 'synthetic-password');
            }
            response = status == 'missing'
                ? null
                : status == 'malformed'
                ? <Object>[]
                : state;
          } else if (r.url.path == '/auth/v1/logout') {
            return http.Response('', 204, request: r);
          } else if (r.url.path == '/auth/v1/user' &&
              ['valid', 'profile_pending', 'switch_after_password',
                'switch_during_marker', 'aba_password', 'aba_marker'].contains(status)) {
            expect(r.headers['authorization'], 'Bearer $token');
            if (status == 'switch_after_password') {
              await client.auth.signOut(scope: SignOutScope.local);
            }
            if (status == 'aba_password') {
              await client.auth.signOut(scope: SignOutScope.local);
              await client.auth.signInWithPassword(email: 'synthetic@example.invalid', password: 'synthetic-password');
            }
            response = {'user': user};
          } else if (r.url.path ==
                  '/rest/v1/rpc/mark_employee_initial_password_changed' &&
              ['valid', 'profile_pending', 'switch_during_marker', 'aba_marker'].contains(status)) {
            expect(r.headers['authorization'], 'Bearer $token');
            if (status == 'switch_during_marker') {
              await client.auth.signOut(scope: SignOutScope.local);
            }
            if (status == 'aba_marker') {
              await client.auth.signOut(scope: SignOutScope.local);
              await client.auth.signInWithPassword(email: 'synthetic@example.invalid', password: 'synthetic-password');
            }
            response = null;
          } else {
            fail('Unexpected mutation: ${r.url.path}');
          }
          return http.Response(
            jsonEncode(response),
            200,
            headers: {'content-type': 'application/json'},
            request: r,
          );
        }),
      );
      if (status != 'missing_session') {
        await client.auth.signInWithPassword(
          email: 'synthetic@example.invalid',
          password: 'synthetic-password',
        );
      }
      final future = SecureOnboardingRepository.forClient(
        client,
      ).setEmployeePrimaryPassword('synthetic-new-password');
      if (['valid', 'profile_pending'].contains(status)) {
        await future;
        expect(calls, [
          '/auth/v1/token',
          '/rest/v1/rpc/employee_onboarding_state',
          '/auth/v1/user',
          '/rest/v1/rpc/mark_employee_initial_password_changed',
        ]);
      } else if (['aba_preflight', 'aba_password', 'aba_marker'].contains(status)) {
        await expectLater(future, throwsStateError);
        expect(client.auth.currentSession?.accessToken, token);
        expect(calls, [
          '/auth/v1/token',
          '/rest/v1/rpc/employee_onboarding_state',
          if (status != 'aba_preflight') '/auth/v1/user',
          if (status == 'aba_marker') '/rest/v1/rpc/mark_employee_initial_password_changed',
          '/auth/v1/logout',
          '/auth/v1/token',
        ]);
      } else if (['switch_after_password', 'switch_during_marker'].contains(status)) {
        await expectLater(future, throwsA(anyOf(isA<StateError>(), isA<AuthException>())));
        expect(calls, [
          '/auth/v1/token',
          '/rest/v1/rpc/employee_onboarding_state',
          '/auth/v1/user',
          if (status == 'switch_during_marker')
            '/rest/v1/rpc/mark_employee_initial_password_changed',
          '/auth/v1/logout',
        ]);
      } else {
        await expectLater(
          future,
          status == 'network_error'
              ? throwsA(isA<http.ClientException>())
              : status == 'state_error'
              ? throwsA(isA<PostgrestException>())
              : throwsStateError,
        );
        expect(
          calls,
          status == 'missing_session'
              ? <String>[]
              : [
                  '/auth/v1/token',
                  '/rest/v1/rpc/employee_onboarding_state',
                  if (status == 'switch_session') '/auth/v1/logout',
                ],
        );
      }
      await client.dispose();
    });
  }
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sk_works/features/payroll/individual_payroll_settings_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const actorA = '10000000-0000-0000-0000-000000000001';
const actorB = '10000000-0000-0000-0000-000000000002';
const workerId = '20000000-0000-0000-0000-000000000001';
const companyId = '30000000-0000-0000-0000-000000000001';

String token(String actor) {
  String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part({
    'sub': actor, 'role': 'authenticated',
    'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
  })}.synthetic';
}

void main() {
  late SupabaseClient client;
  late IndividualPayrollSettingsRepository repository;
  late List<http.Request> requests;
  Map<String, dynamic>? saved;
  var visible = true;
  var denied = false;
  var actor = actorA;
  Future<void> Function()? duringLookup;

  Future<void> login() async {
    await client.auth.signInWithPassword(email: 'fixture@example.test', password: 'fixture');
  }

  setUp(() {
    requests = [];
    saved = null;
    visible = true;
    denied = false;
    actor = actorA;
    duringLookup = null;
    client = SupabaseClient('https://fixture.invalid', 'synthetic-public-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        Object body;
        var status = 200;
        switch (request.url.path) {
          case '/auth/v1/token':
            body = {'access_token': token(actor), 'refresh_token': 'fixture-refresh',
              'expires_in': 3600, 'token_type': 'bearer', 'user': {
                'id': actor, 'aud': 'authenticated', 'app_metadata': {},
                'user_metadata': {}, 'created_at': '2026-10-19T00:00:00Z'}};
          case '/rest/v1/workers':
            expect(request.method, 'GET');
            expect(request.url.queryParameters['id'], 'eq.$workerId');
            expect(request.url.queryParameters['select'], 'company_id');
            final callback = duringLookup;
            duringLookup = null;
            await callback?.call();
            body = visible ? [{'company_id': companyId}] : [];
          case '/rest/v1/worker_payroll_settings':
            expect(request.method, 'POST');
            expect(request.url.queryParameters['on_conflict'], 'worker_id');
            saved = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
            status = denied ? 403 : 201;
            body = denied ? {'code': '42501', 'message': 'fixture RLS denial'} : {};
          default:
            throw StateError('Unexpected fixture endpoint ${request.url.path}');
        }
        return http.Response(jsonEncode(body), status,
          headers: {'content-type': 'application/json'}, request: request);
      }), authOptions: const AuthClientOptions(autoRefreshToken: false));
    repository = IndividualPayrollSettingsRepository.forTesting(client);
  });
  tearDown(() => client.dispose());

  test('save resolves the selected worker company instead of a first membership', () async {
    await login();
    await repository.saveSetting(workerId: workerId, values: {'day_daily': 20000});
    expect(saved!['company_id'], companyId);
    expect(saved!['worker_id'], workerId);
    expect(saved!['day_daily'], 20000);
    expect(requests.any((r) => r.url.path.endsWith('/company_members')), isFalse);
  });

  test('input values cannot replace the resolved worker and company', () async {
    await login();
    await repository.saveSetting(workerId: workerId, values: {
      'worker_id': actorB, 'company_id': actorB, 'day_daily': 20000,
    });
    expect(saved!['company_id'], companyId);
    expect(saved!['worker_id'], workerId);
  });

  test('hidden worker stops before any salary write', () async {
    await login();
    visible = false;
    await expectLater(repository.saveSetting(workerId: workerId, values: {}), throwsStateError);
    expect(saved, isNull);
  });

  test('actor change during company lookup stops the write', () async {
    await login();
    duringLookup = () async { actor = actorB; await login(); };
    await expectLater(repository.saveSetting(workerId: workerId, values: {}), throwsStateError);
    expect(saved, isNull);
  });

  test('anonymous caller never queries salary or worker data', () async {
    await expectLater(repository.saveSetting(workerId: workerId, values: {}), throwsStateError);
    expect(requests, isEmpty);
  });

  test('server RLS denial is propagated without retry or other company fallback', () async {
    await login();
    denied = true;
    await expectLater(repository.saveSetting(workerId: workerId, values: {}), throwsA(isA<PostgrestException>()));
    expect(requests.where((r) => r.url.path.endsWith('/worker_payroll_settings')), hasLength(1));
  });
}

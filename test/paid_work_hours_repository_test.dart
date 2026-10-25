import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sk_works/features/attendance/paid_work_hours_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const actor = '00000000-0000-0000-0000-000000000001';
const company = '00000000-0000-0000-0000-000000000002';
const worker = '00000000-0000-0000-0000-000000000003';
const report = '00000000-0000-0000-0000-000000000004';
const other = '00000000-0000-0000-0000-000000000099';

String token(String uid) {
  String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part({'sub': uid, 'role': 'authenticated', 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.fixture';
}
Map<String, dynamic> response() => {
  'schema': 1, 'actor_id': actor, 'company_id': company, 'worker_id': worker,
  'report_id': report, 'work_date': '2026-10-10', 'revision': 1,
  'scope_fingerprint': List.filled(64, 'a').join(), 'required': true,
  'editable': true, 'source_blocked': false, 'input_scope_current': true,
  'source_reasons': <String>[], 'hours': null,
};

class Fixture {
  String loginActor = actor;
  bool changeActorDuringRead = false, wrongScope = false;
  final tokens = <String, String>{};
  final rpcRequests = <Map<String, dynamic>>[];
  late final client = SupabaseClient('https://synthetic.invalid', 'fixture-only',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient(handle));
  PaidWorkHoursRepository get repository => PaidWorkHoursRepository(client);

  Future<void> login([String uid = actor]) async {
    loginActor = uid;
    await client.auth.signInWithPassword(email: 'synthetic@example.invalid', password: 'fixture-only-password');
    await Future<void>.delayed(Duration.zero);
  }

  Future<http.Response> handle(http.Request request) async {
    Object result;
    if (request.url.path.endsWith('/token')) {
      result = {'access_token': tokens.putIfAbsent(loginActor, () => token(loginActor)), 'refresh_token': 'fixture-only', 'token_type': 'bearer', 'expires_in': 3600,
        'user': {'id': loginActor, 'aud': 'authenticated', 'role': 'authenticated', 'email': 'synthetic@example.invalid',
          'app_metadata': {'provider': 'email'}, 'user_metadata': <String, dynamic>{}, 'created_at': '2026-10-01T00:00:00Z'}};
    } else if (request.url.path.endsWith('/logout')) {
      result = <String, dynamic>{};
    } else {
      expect(request.method, 'POST');
      expect(request.url.path.split('/').last, anyOf('read_checkout_paid_work_hours', 'save_checkout_paid_work_hours'));
      final parameters = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
      rpcRequests.add(parameters);
      if (changeActorDuringRead) {
        changeActorDuringRead = false;
        await login(other);
        await login(actor);
      }
      final row = response();
      if (parameters.containsKey('p_hours')) {
        row['hours'] = parameters['p_hours'];
        row['revision'] = 2;
      }
      if (wrongScope) row['worker_id'] = other;
      result = row;
    }
    return http.Response(jsonEncode(result), 200, headers: {'content-type': 'application/json'}, request: request);
  }
}

void main() {
  late Fixture fixture;
  setUp(() => fixture = Fixture());
  tearDown(() async => fixture.client.dispose());
  Future<PaidWorkHoursSnapshot> load() => fixture.repository.load(companyId: company, workerId: worker, reportId: report);

  test('missing session does not issue any RPC', () async {
    await expectLater(load(), throwsStateError);
    expect(fixture.rpcRequests, isEmpty);
  });
  test('read binds all server scope and keeps unknown hours null', () async {
    await fixture.login();
    expect((await load()).hours, isNull);
    expect(fixture.rpcRequests, [{'p_report_id': report, 'p_worker_id': worker}]);
  });
  test('save sends explicit zero and exact revision/source CAS', () async {
    await fixture.login();
    final before = await load();
    final saved = await fixture.repository.save(before, '0');
    expect(saved.hours, 0);
    expect(saved.revision, 2);
    expect(fixture.rpcRequests.last, {
      'p_report_id': report, 'p_worker_id': worker, 'p_hours': 0.0,
      'p_expected_revision': 1, 'p_expected_scope': before.scopeFingerprint,
    });
  });
  test('unknown result scope is rejected instead of updating current report', () async {
    await fixture.login();
    fixture.wrongScope = true;
    await expectLater(load(), throwsStateError);
  });
  test('async A to B to A session transition invalidates the pending request', () async {
    await fixture.login();
    final originalToken = fixture.client.auth.currentSession!.accessToken;
    fixture.changeActorDuringRead = true;
    await expectLater(load(), throwsStateError);
    expect(fixture.client.auth.currentUser?.id, actor);
    expect(fixture.client.auth.currentSession?.accessToken, originalToken);
  });
  test('empty, negative, excessive precision and nonfinite inputs never save', () async {
    await fixture.login();
    final before = await load();
    final count = fixture.rpcRequests.length;
    for (final text in ['', '-1', '24.1', '7.12345', 'NaN', 'Infinity']) {
      expect(() => fixture.repository.save(before, text), throwsFormatException);
    }
    expect(fixture.rpcRequests.length, count);
  });
}

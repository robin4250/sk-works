import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sk_works/features/settings/company_common_rates_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const company = '10000000-0000-0000-0000-000000000001';
const actor = '20000000-0000-0000-0000-000000000001';
const otherActor = '20000000-0000-0000-0000-000000000002';
const rid = '80000000-0000-4000-8000-000000000001';
Map<String, dynamic> fixture() => commonRatesObject(jsonDecode(File('test/fixtures/company_common_rates_sql_response.json').readAsStringSync()));
CompanyCommonRatesRequest request() => CompanyCommonRatesRequest.parse({
 'journal_version':1,'company_id':company,'actor_id':actor,'request_id':rid,
 'request_payload':commonRatesObject(fixture()['receipt'])['request_payload']},company,actor);
String _token(String user) {
  String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.${part({'sub': user, 'session_id': '70000000-0000-0000-0000-000000000001',
    'role': 'authenticated', 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.synthetic';
}
class Wire {
  Wire() {
    client = SupabaseClient('https://common-rates-fixture.invalid', 'public_fixture',
      authOptions: const AuthClientOptions(autoRefreshToken: false), httpClient: MockClient((r) async {
        calls.add(r); final response = await respond(r);
        return http.Response.bytes(response.bodyBytes, response.statusCode, headers: response.headers, request: r);
      }));
    repository = SupabaseCompanyCommonRatesRepository(client);
  }
  late final SupabaseClient client;
  late final SupabaseCompanyCommonRatesRepository repository;
  String currentActor = actor;
  final calls = <http.Request>[];
  String? errorCode;
  Object? overrideSave;
  Future<void> Function()? duringSave;
  Future<void> login() => client.auth.signInWithPassword(phone: '+810000000000', password: 'synthetic').then((_) {});
  http.Response json(Object? value, [int status = 200]) => http.Response(jsonEncode(value), status, headers: {'content-type': 'application/json'});
  Future<http.Response> respond(http.Request r) async {
    if (r.url.path == '/auth/v1/token') {
      return json({'access_token': _token(currentActor), 'refresh_token': 'synthetic', 'token_type': 'bearer', 'expires_in': 3600,
        'user': {'id': currentActor, 'aud': 'authenticated', 'app_metadata': {}, 'user_metadata': {}, 'created_at': '2026-10-16T00:00:00Z'}});
    }
    if (errorCode != null) return json({'code': errorCode, 'message': 'synthetic'}, errorCode == 'PGRST202' ? 404 : 403);
    if (r.url.path.endsWith('/read_company_common_rate_settings')) return json(fixture()['initial']);
    if (r.url.path.endsWith('/save_company_common_rates_settings')) {
      await duringSave?.call(); return json(overrideSave ?? fixture()['result']);
    }
    if (r.url.path.endsWith('/read_company_common_allowance_request')) return json(fixture()['receipt']);
    throw StateError('Unexpected endpoint: legacy fallback forbidden');
  }
}
void main() {
  test('locked SDK uses only the new scoped patch with exact source and four integer rates, request UUID and original bearer', () async {
    final w = Wire(); addTearDown(w.client.dispose); await w.login();
    final bearer = 'Bearer ${w.client.auth.currentSession!.accessToken}';
    expect((await w.repository.read(company)).rates['overtime_hour_rate_yen'], 0);
    expect((await w.repository.save(request())).rates['overtime_hour_rate_yen'], 5125);
    final write = w.calls.singleWhere((r) => r.url.path.endsWith('/save_company_common_rates_settings'));
    expect(write.headers['authorization'], bearer);
    expect(jsonDecode(write.body), {'p_company_id': company, 'p_expected_version': 0,
      'p_expected_rates': request().expectedRates, 'p_rates': request().rates, 'p_request_id': rid});
    expect((await w.repository.receipt(request()))!.version, 1);
    final read = w.calls.last;
    expect(jsonDecode(read.body), {'p_company_id': company, 'p_request_id': rid});
    expect(w.calls.where((r) => r.url.path.contains('save_company_rate_settings')), isEmpty);
  });
  test('missing new RPC is unavailable and permission failures never fall back to the old full saver', () async {
    final w = Wire(); addTearDown(w.client.dispose); await w.login();
    w.errorCode = 'PGRST202';
    await expectLater(w.repository.read(company), throwsA(isA<CompanyCommonRatesUnavailable>()));
    await expectLater(w.repository.save(request()), throwsA(isA<CompanyCommonRatesUnavailable>()));
    w.errorCode = '42501';
    await expectLater(w.repository.read(company), throwsA(isA<PostgrestException>()));
    expect(w.calls.where((r) => r.url.path.contains('save_company_rate_settings')), isEmpty);
  });
  test('actor switch rejects late mutation result and cannot dispatch another actor journal', () async {
    final w = Wire(); addTearDown(w.client.dispose); await w.login();
    final original = 'Bearer ${w.client.auth.currentSession!.accessToken}';
    w.duringSave = () async { w.currentActor = otherActor; await w.login(); };
    await expectLater(w.repository.save(request()), throwsStateError);
    expect(w.calls.singleWhere((r) => r.url.path.endsWith('/save_company_common_rates_settings')).headers['authorization'], original);
    final count = w.calls.length;
    await expectLater(w.repository.save(request()), throwsStateError);
    expect(w.calls.length, count);
  });
  test('malformed successful response is unknown, not successful or an automatic resend', () async {
    final w = Wire(); addTearDown(w.client.dispose); await w.login();
    w.overrideSave = {...commonRatesObject(fixture()['result']), 'request_id': '40000000-0000-4000-8000-000000000099'};
    await expectLater(w.repository.save(request()), throwsFormatException);
    expect(w.calls.where((r) => r.url.path.endsWith('/save_company_common_rates_settings')).length, 1);
  });
}


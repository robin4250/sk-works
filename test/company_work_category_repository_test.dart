import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sk_works/features/settings/company_work_category_policy.dart';
import 'package:sk_works/features/settings/company_work_category_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const actor = '00000000-0000-0000-0000-000000000001';
const company = '00000000-0000-0000-0000-000000000002';
const worker = '00000000-0000-0000-0000-000000000003';
const source = '00000000-0000-0000-0000-000000000004';
const other = '00000000-0000-0000-0000-000000000099';
const sid = '00000000-0000-0000-0000-000000000100';
const otherSid = '00000000-0000-0000-0000-000000000101';
String token(String uid, String session, int generation) {
  String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part({'sub': uid, 'session_id': session, 'role': 'authenticated', 'iat': generation, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.fixture';
}
class Fixture {
  String uid = actor, session = sid;
  int generation = 0, readCount = 0, saveCount = 0, sourceCount = 0;
  bool aba = false, refresh = false;
  String? switchSession;
  late final client = SupabaseClient('https://synthetic.invalid', 'fixture-only', authOptions: const AuthClientOptions(autoRefreshToken: false), httpClient: MockClient(handle));
  late final repository = CompanyWorkCategoryRepository(client);
  Map<String, dynamic> policy = CompanyWorkCategoryPolicy.editingSeed.toJson();
  Map<String, dynamic> raw = {'schema': 1, 'actor_id': actor, 'company_id': company, 'revision': 1, 'can_manage': true};
  Map<String, dynamic> sourceRow = {'id': source, 'company_id': company, 'worker_id': worker, 'event_type': 'clock_in', 'work_date': '2026-10-27', 'confirmed_at': '2026-10-27T13:00:00Z'};
  Map<String, dynamic>? savedBody;
  Future<void> login({String user = actor, String sessionId = sid, bool flush = true}) async {
    uid = user; session = sessionId;
    await client.auth.signInWithPassword(email: 'synthetic@example.invalid', password: 'fixture-only-password');
    if (flush) await Future<void>.delayed(Duration.zero);
  }
  Future<http.Response> handle(http.Request request) async {
    Object? value;
    if (request.url.path.endsWith('/token')) {
      value = {'access_token': token(uid, session, generation++), 'refresh_token': 'fixture-only', 'token_type': 'bearer', 'expires_in': 3600,
        'user': {'id': uid, 'aud': 'authenticated', 'role': 'authenticated', 'email': 'synthetic@example.invalid', 'app_metadata': {'provider': 'email'}, 'user_metadata': <String,dynamic>{}, 'created_at': '2026-10-01T00:00:00Z'}};
    } else {
      if (aba) { aba = false; await login(user: other, sessionId: otherSid, flush: false); await login(flush: false); }
      if (switchSession != null) { final next = switchSession!; switchSession = null; await login(sessionId: next); }
      if (refresh) { refresh = false; await client.auth.refreshSession(); }
      if (request.url.path.endsWith('/read_company_work_category_policy')) {
        readCount++; expect(request.method, 'POST'); expect(jsonDecode(request.body), {'p_company_id': company});
        value = {...raw, 'policy': raw['revision'] == 0 ? null : policy};
      } else if (request.url.path.endsWith('/save_company_work_category_policy')) {
        saveCount++; savedBody = Map<String,dynamic>.from(jsonDecode(request.body) as Map);
        value = {...raw, 'revision': (raw['revision'] as int) + 1, 'policy': savedBody!['p_policy']};
      } else {
        sourceCount++; expect(request.method, 'GET'); expect(request.url.path.endsWith('/attendance_verifications'), true);
        expect(request.url.queryParameters['id'], 'eq.$source'); expect(request.url.queryParameters['company_id'], 'eq.$company');
        expect(request.url.queryParameters['worker_id'], 'eq.$worker'); expect(request.url.queryParameters['event_type'], 'eq.clock_in');
        value = [sourceRow];
      }
    }
    return http.Response(jsonEncode(value), 200, headers: {'content-type':'application/json'}, request: request);
  }
}
void main() {
  late Fixture f;
  setUp(() => f = Fixture());
  tearDown(() async => f.client.dispose());
  Future<CompanyWorkCategorySnapshot> load() => f.repository.load(company);
  Future<String?> propose(CompanyWorkCategorySnapshot snapshot) => f.repository.proposeForSource(snapshot, sourceClockInId: source, workerId: worker, workDate: DateTime(2026,10,27));
  test('new source uses real clock-in and sends no write', () async {
    await f.login(); final before = await load(); expect(await propose(before), 'night'); expect(f.saveCount, 0);
  });
  test('unconfigured policy never uses editing seed', () async {
    await f.login(); f.raw['revision'] = 0; final before = await load(); expect(await propose(before), isNull); expect(f.sourceCount, 0);
  });
  test('source identity and timezone are mandatory', () async {
    await f.login(); final before = await load(); final original = {...f.sourceRow};
    for (final bad in [{'worker_id':other},{'company_id':other},{'id':other},{'event_type':'clock_out'},{'work_date':'2026-10-26'},{'work_date':null},{'confirmed_at':'2026-10-27T22:00:00'}]) {
      f.sourceRow = {...original,...bad}; expect(await propose(before), isNull);
    }
  });
  test('save is CAS bound to exact company revision', () async {
    await f.login(); final before = await load(); final saved = await f.repository.save(before, before.policy!);
    expect(saved.revision, 2); expect(f.savedBody!['p_company_id'],company); expect(f.savedBody!['p_expected_revision'],1);
  });
  test('viewer cannot start settings write', () async {
    await f.login(); f.raw['can_manage'] = false; final before = await load(); expect(() => f.repository.save(before, before.policy!), throwsStateError); expect(f.saveCount,0);
  });
  test('changed session between load and save cannot reuse old form', () async {
    await f.login(); final before = await load(); await f.login(sessionId:otherSid);
    expect(() => f.repository.save(before, before.policy!), throwsStateError); expect(await propose(before),isNull); expect(f.saveCount,0);
  });
  test('A B A event history invalidates in-flight policy', () async {
    await f.login(); f.aba = true; await expectLater(load(),throwsStateError);
  });
  test('A B A event history invalidates in-flight clock-in proposal', () async {
    await f.login(); final before = await load(); f.aba = true; expect(await propose(before),isNull);
  });
  test('different session invalidates pending result', () async {
    await f.login(); f.switchSession = otherSid; await expectLater(load(),throwsStateError);
  });
  test('normal token refresh in same session preserves proposal', () async {
    await f.login(); f.refresh = true; final before = await load(); f.refresh = true; expect(await propose(before),'night');
  });
}

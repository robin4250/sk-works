import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sk_works/features/daily_reports/daily_report_company_allowance_selection.dart';
import 'package:sk_works/features/daily_reports/daily_report_repository.dart';
import 'package:sk_works/features/daily_reports/shared_worker_facts_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const actor = '00000000-0000-0000-0000-000000000001';
const company = '00000000-0000-0000-0000-000000000002';
const worker = '00000000-0000-0000-0000-000000000003';
const report = '00000000-0000-0000-0000-000000000004';
const other = '00000000-0000-0000-0000-000000000099';
const sid = '00000000-0000-0000-0000-000000000100';
const otherSid = '00000000-0000-0000-0000-000000000101';

Map<String, dynamic> facts() => <String, dynamic>{'schema': 1,
  'overtime_hours': 0, 'early_hours': 0, 'night_hours': 0, 'work_category': 'day',
  'allowance_amount': 500, 'allowance_label': '保存済み個別手当',
  'company_allowance_selections': <String, dynamic>{'contract_version': 1, 'items': <dynamic>[]},
  'company_allowance_legacy_labels': '保存済み個別手当',
  'vehicle_id': null, 'route_assignment_id': null, 'odometer_km': null};

Map<String, dynamic> response() => <String, dynamic>{
  'schema': 1, 'contract_version': 2, 'actor_id': actor, 'company_id': company,
  'worker_id': worker, 'report_id': report, 'work_date': '2026-10-22',
  'revision': 0, 'scope_fingerprint': List.filled(64, 'a').join(),
  'required': true, 'editable': true, 'source_blocked': false,
  'input_scope_current': true, 'source_reasons': <String>[], 'hours': null,
  'report_status': 'draft', 'work_report_frozen': true, 'first_reporter_covers_work_only': true,
  'work_basis_sha256': List.filled(64, 'b').join(), 'own_worker': true,
  'management_confirmation_available': false, 'facts_confirmed': false,
  'hours_required_outside_current_report': false,
  'facts_current': false, 'worker_facts': null, 'proposed_worker_facts': facts(),
};

SharedWorkerFactsSnapshot parse(Object? row) => SharedWorkerFactsSnapshot.parse(row,
  actorId: actor, companyId: company, workerId: worker, reportId: report);

String token(String uid, String session, int generation) {
  String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part({'sub': uid,
    'session_id': session, 'role': 'authenticated', 'iat': generation,
    'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.fixture';
}

class Fixture {
  String loginUid = actor, loginSid = sid;
  int generation = 0;
  bool queuedAba = false, switchSid = false, refreshToken = false;
  String? rpcError;
  final rpcRequests = <Map<String, dynamic>>[];
  final rpcNames = <String>[];
  late final client = SupabaseClient('https://synthetic.invalid', 'fixture-only',
    authOptions: const AuthClientOptions(autoRefreshToken: false), httpClient: MockClient(handle));
  SharedWorkerFactsRepository get repository => SharedWorkerFactsRepository(client);

  Future<void> login({String uid = actor, String session = sid, bool flush = true}) async {
    loginUid = uid; loginSid = session;
    await client.auth.signInWithPassword(email: 'synthetic@example.invalid', password: 'fixture-only-password');
    if (flush) { await Future<void>.delayed(Duration.zero); }
  }

  Future<http.Response> handle(http.Request request) async {
    Object result;
    if (request.url.path.endsWith('/token')) {
      result = {'access_token': token(loginUid, loginSid, generation++), 'refresh_token': 'fixture-only',
        'token_type': 'bearer', 'expires_in': 3600,
        'user': {'id': loginUid, 'aud': 'authenticated', 'role': 'authenticated',
          'email': 'synthetic@example.invalid', 'app_metadata': {'provider': 'email'},
          'user_metadata': <String, dynamic>{}, 'created_at': '2026-10-01T00:00:00Z'}};
    } else {
      final name = request.url.path.split('/').last;
      expect(name, anyOf('read_shared_worker_facts', 'confirm_shared_worker_facts', 'confirm_managed_shared_worker_facts'));
      expect(request.method, 'POST');
      final body = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
      rpcNames.add(name); rpcRequests.add(body);
      if (rpcError != null) {
        return http.Response(jsonEncode({'code': rpcError, 'message': 'synthetic private SQL source',
          'details': 'synthetic details'}), rpcError == 'PT409' ? 409 : 403,
          headers: {'content-type': 'application/json'}, request: request);
      }
      if (queuedAba) {
        queuedAba = false;
        await login(uid: other, session: otherSid, flush: false);
        await login(flush: false);
      }
      if (switchSid) { switchSid = false; await login(session: otherSid); }
      if (refreshToken) { refreshToken = false; await client.auth.refreshSession(); }
      final row = response();
      if (body.containsKey('p_facts')) {
        row['worker_facts'] = Map<String, dynamic>.from(body['p_facts'] as Map)
          ..['company_allowance_legacy_labels'] = '保存済み個別手当';
        row['facts_confirmed'] = true; row['facts_current'] = true;
        row['hours'] = body['p_hours']; row['revision'] = 1;
      }
      result = row;
    }
    return http.Response(jsonEncode(result), 200, headers: {'content-type': 'application/json'}, request: request);
  }
}

void main() {
  test('explicit zero is valid and derived labels are not writable input', () {
    final value = SharedWorkerFacts.parse(facts());
    expect(value.overtimeHours, 0);
    expect(value.toConfirmationJson().containsKey('company_allowance_legacy_labels'), false);
    expect(value.toConfirmationJson()['allowance_amount'], 500);
  });
  test('missing numeric values do not become zero', () {
    for (final key in ['overtime_hours', 'early_hours', 'night_hours', 'allowance_amount']) {
      expect(() => SharedWorkerFacts.parse(facts()..remove(key)), throwsFormatException);
      expect(() => SharedWorkerFacts.parse(facts()..[key] = null), throwsFormatException);
    }
  });
  test('invalid field types and unregistered choices fail closed', () {
    for (final update in <Map<String, dynamic>>[
      {'overtime_hours': double.nan}, {'early_hours': -1}, {'night_hours': 25},
      {'allowance_amount': 500.5}, {'work_category': 'unknown'},
      {'company_allowance_selections': null}, {'odometer_km': 100},
    ]) {
      expect(() => SharedWorkerFacts.parse(facts()..addAll(update)), throwsFormatException);
    }
  });
  test('canonical facts reject unknown keys and versions', () {
    expect(() => SharedWorkerFacts.parse(facts()..['rate_yen'] = 999999), throwsFormatException);
    expect(() => SharedWorkerFacts.parse(facts()..['schema'] = 2), throwsFormatException);
  });
  test('draft with unknown choices is not treated as an empty selection', () {
    expect(() => SharedWorkerFacts.fromDraft(DailyReportWorkerDraft(workerId: worker,
      workerName: '合成社員'), workCategory: 'day'), throwsFormatException);
    expect(SharedWorkerFacts.fromDraft(DailyReportWorkerDraft(workerId: worker,
      workerName: '合成社員', companyAllowanceSelections: DailyReportCompanyAllowanceSelections([])),
      workCategory: 'day').companyAllowanceSelections.items, isEmpty);
  });
  test('facts copy preserves source metadata without changing another worker', () {
    final original = DailyReportWorkerDraft(workerId: worker, workerName: '合成社員',
      sourceClockInId: other, sourceClockOutAt: DateTime.utc(2026, 10, 22, 8));
    final value = SharedWorkerFacts.parse(facts());
    final copy = value.toDraft(workerId: worker, workerName: '合成社員', template: original);
    expect(copy.sourceClockInId, other);
    expect(copy.sourceClockOutAt, original.sourceClockOutAt);
    expect(() => value.toDraft(workerId: actor, workerName: '別人', template: original), throwsFormatException);
  });
  test('proposal is not an actual confirmation and unknown hours stay null', () {
    final value = parse(response());
    expect(value.confirmed, false); expect(value.current, false);
    expect(value.hoursRequiredOutsideCurrentReport, false);
    expect(parse(response()..['hours_required_outside_current_report'] = true)
      .hoursRequiredOutsideCurrentReport, true);
    expect(value.facts, isNull); expect(value.proposedFacts, isNotNull); expect(value.hours, isNull);
  });
  test('all actor and document identities are bound', () {
    for (final key in ['actor_id', 'company_id', 'worker_id', 'report_id']) {
      expect(() => parse(response()..[key] = other), throwsStateError);
    }
  });
  test('missing confirmation and role flags cannot be inferred', () {
    for (final key in ['facts_confirmed', 'facts_current', 'own_worker', 'management_confirmation_available',
      'hours_required_outside_current_report']) {
      expect(() => parse(response()..remove(key)), throwsFormatException);
    }
  });
  test('claimed confirmation requires saved facts and contract two', () {
    expect(() => parse(response()..['facts_confirmed'] = true), throwsFormatException);
    expect(() => parse(response()..['contract_version'] = 1), throwsFormatException);
    expect(() => parse(response()..['facts_current'] = true), throwsFormatException);
  });

  late Fixture fixture;
  setUp(() => fixture = Fixture());
  tearDown(() async => fixture.client.dispose());
  Future<SharedWorkerFactsSnapshot> load() => fixture.repository.load(companyId: company, reportId: report, workerId: worker);
  test('missing session issues no request', () async {
    await expectLater(load(), throwsStateError); expect(fixture.rpcRequests, isEmpty);
  });
  test('explicit confirmation sends bound facts and revision without derived labels', () async {
    await fixture.login();
    final before = await load();
    final saved = await fixture.repository.confirm(before, before.proposedFacts!, hours: 7.25);
    expect(saved.confirmed, true); expect(saved.current, true); expect(saved.hours, 7.25);
    final body = fixture.rpcRequests.last;
    expect(body['p_expected_revision'], 0); expect(body['p_expected_scope'], before.scopeFingerprint);
    expect(body['p_report_id'], report); expect(body['p_worker_id'], worker);
    expect((body['p_facts'] as Map).containsKey('company_allowance_legacy_labels'), false);
  });
  test('unknown required hours are not submitted as zero', () async {
    await fixture.login(); final before = await load();
    expect(() => fixture.repository.confirm(before, before.proposedFacts!), throwsFormatException);
    expect(fixture.rpcNames, ['read_shared_worker_facts']);
  });
  test('manager reason does not create a role the server did not return', () async {
    await fixture.login(); final before = await load();
    expect(() => fixture.repository.confirm(before, before.proposedFacts!, hours: 7.25,
      managementReason: '合成補正'), throwsFormatException);
    expect(fixture.rpcNames, ['read_shared_worker_facts']);
  });
  test('same UID but a different session cancels the result', () async {
    await fixture.login(); fixture.switchSid = true;
    await expectLater(load(), throwsStateError);
  });
  test('queued A to B to A events invalidate the pending result', () async {
    await fixture.login(); fixture.queuedAba = true;
    await expectLater(load(), throwsStateError);
  });
  test('ordinary access-token refresh in the same UID and SID remains valid', () async {
    await fixture.login(); fixture.refreshToken = true;
    expect((await load()).workerId, worker);
  });
  test('server CAS conflict is localized without leaking SQL text', () async {
    await fixture.login(); fixture.rpcError = 'PT409';
    await expectLater(load(), throwsA(isA<StateError>().having((e) => e.message,
      'safe conflict message', '勤務実績が更新されました。再読込して確認してください。')));
  });
  test('server role denial is localized without leaking SQL text', () async {
    await fixture.login(); fixture.rpcError = '42501';
    await expectLater(load(), throwsA(isA<StateError>().having((e) => e.message,
      'safe denial message', 'この勤務実績を登録する権限を確認できません。')));
  });
}

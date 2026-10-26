import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/daily_reports/shared_daily_report_repository.dart';
import 'package:sk_works/features/daily_reports/daily_report_repository.dart';
import 'package:sk_works/features/daily_reports/route_visit_report_context.dart';

const _actor = '00000000-0000-0000-0000-000000000001';
const _company = '00000000-0000-0000-0000-000000000002';
const _worker = '00000000-0000-0000-0000-000000000003';
const _report = '00000000-0000-0000-0000-000000000004';
const _source = '00000000-0000-0000-0000-000000000005';
final _stamp = DateTime.utc(2026, 10, 26, 3, 4, 5, 123, 456);
final _scope = List.filled(64, 'a').join();

class _RpcFixture {
  bool explicit = false, document = false, complete = false, route = false, switchAba = false;
  String loginUid = _actor;
  int generation = 0;
  final calls = <String>[];
  final requests = <Map<String, dynamic>>[];
  late final client = SupabaseClient('https://synthetic.invalid', 'fixture-only',
    authOptions: const AuthClientOptions(autoRefreshToken: false), httpClient: MockClient(handle));
  SharedDailyReportRepository get repository => SharedDailyReportRepository(client);
  Future<void> login() async {
    await client.auth.signInWithPassword(email: 'fixture@example.invalid', password: 'fixture-only');
    await Future<void>.delayed(Duration.zero);
  }
  Future<http.Response> handle(http.Request request) async {
    Object row;
    if (request.url.path.endsWith('/token')) {
      String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
      final token = '${part({'alg': 'HS256'})}.${part({'sub': loginUid, 'iat': generation++, 'role': 'authenticated',
        'session_id': _source, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.fixture';
      row = {'access_token': token, 'refresh_token': 'fixture-only', 'token_type': 'bearer', 'expires_in': 3600,
        'user': {'id': loginUid, 'aud': 'authenticated', 'role': 'authenticated',
          'email': 'fixture@example.invalid', 'app_metadata': {}, 'user_metadata': {}, 'created_at': '2026-10-26T00:00:00Z'}};
    } else {
      calls.add(request.url.path.split('/').last);
      requests.add(Map<String, dynamic>.from(jsonDecode(request.body) as Map));
      if (switchAba) {
        switchAba = false; loginUid = _company; await login(); loginUid = _actor; await login();
      }
      row = route ? visitResponse() : response();
    }
    return http.Response(jsonEncode(row), 200, headers: {'content-type': 'application/json'}, request: request);
  }
  Map<String, dynamic> visitResponse() => {'id': _report, 'company_id': _company,
    'source_clock_in_id': _source, 'route_assignment_id': 'route', 'route_stop_id': 'stop',
    'start_capture_id': 'arrival', 'end_capture_id': 'move', 'site_id': 'site', 'site_name': '訪問現場',
    'report_date': '2026-10-26', 'status': complete ? 'completed' : 'reporter_signed',
    'work_description': '実際の訪問作業', 'representative_signer_name': '報告者',
    'representative_signature_json': {'strokes': [[{'x': 0.1, 'y': 0.2}]]},
    'supervisor_signer_name': '責任者', 'supervisor_signature_json': {'strokes': [[{'x': 0.2, 'y': 0.3}]]},
    'workers': [{'worker_id': _worker, 'worker_name': '本人'}],
    'explicit_finalization_required': true, 'explicit_finalization_ready': !complete,
    'explicit_finalization_completed': complete, 'report_updated_at': _stamp.toIso8601String(),
    'signature_scope_fingerprint': _scope};
  Map<String, dynamic> response() => {'schema': 1, 'actor_id': _actor, 'company_id': _company,
    'worker_id': _worker, 'source_clock_in_id': _source, 'report_id': _report, 'work_date': '2026-10-26',
    'state': complete ? 'supervisor_saved' : document ? 'reporter_required' : 'reporter_saved_waiting_supervisor',
    'enabled': true, 'can_manage_attendance': false, 'reporter_saved': !document,
    'supervisor_saved': complete, 'source_attached': true, 'supervisor_ready': !complete,
    'first_reporter_covers_work_only': true, 'management_hold': false,
    'pending_members': [], 'supervisor_pending_reasons': [], 'reporter_name': '報告者',
    'report_status': complete ? 'signed' : 'draft', 'report_updated_at': _stamp.toIso8601String(),
    'signature_scope_fingerprint': _scope, 'hours_annex': null,
    if (explicit) ...{'explicit_finalization_required': true,
      'explicit_finalization_ready': false, 'explicit_finalization_completed': complete},
    if (document) ...{'document_only': true, 'document_complete': false, 'document_editable': false,
      'financial_confirmation_required': true, 'document_basis': {'report': {'id': _report,
        'company_id': _company, 'report_date': '2026-10-26', 'work_description': '実際の作業'},
        'workers': [{'report_id': _report, 'worker_id': _worker, 'worker_name': '本人'}]}},
    'work_basis': {'contract_version': 2, 'report': {'id': _report, 'company_id': _company,
      'work_date': '2026-10-26', 'site_id': _source, 'route_assignment_id': null,
      'work_description': '実際の作業'}, 'roster': [{'worker_id': _worker}]}};
  SharedDailyReportContext before({bool ready = false}) => SharedDailyReportContext(actorId: _actor,
    companyId: _company, workerId: _worker, reportId: _report, sourceClockInId: _source,
    workDate: DateTime(2026, 10, 26), state: 'reporter_required', enabled: true,
    canManageAttendance: false, reporterSaved: ready, supervisorSaved: ready, sourceAttached: true,
    expectedUpdatedAt: _stamp, signatureScopeFingerprint: _scope, supervisorReady: true,
    explicitFinalizationRequired: explicit, explicitFinalizationReady: ready,
    documentOnly: document, financialConfirmationRequired: document);
}

Map<String, dynamic> _workerInput() => {'worker_id': _worker, 'overtime_hours': 1,
  'early_hours': 0, 'night_hours': 0, 'allowance_amount': 0, 'allowance_label': '',
  'work_category': 'night', 'confirmed_hours': 7.5, 'confirmation_reason': null};

void main() {
  for (final explicit in [false, true]) {
    test('submit sends only the advertised legacy or explicit worker contract: $explicit', () async {
      final fixture = _RpcFixture()..explicit = explicit;
      addTearDown(fixture.client.dispose); await fixture.login();
      await fixture.repository.submit(before: fixture.before(), workDescription: '実際の作業',
        workers: [_workerInput()], signerName: '報告者', signature: {'strokes': [[{'x': 0.1, 'y': 0.2}]]});
      final payload = (fixture.requests.single['p_workers'] as List).single as Map;
      expect(payload.length, explicit ? 9 : 6);
      expect(payload.containsKey('work_category'), explicit);
      expect(payload.containsKey('confirmed_hours'), explicit);
      expect(payload.containsKey('confirmation_reason'), explicit);
      expect(fixture.calls, ['submit_shared_daily_report']);
    });
  }
  test('old document writer retains its six-field worker input contract', () async {
    final fixture = _RpcFixture()..document = true;
    addTearDown(fixture.client.dispose); await fixture.login();
    await fixture.repository.saveDocumentDraft(before: fixture.before(), workDescription: '実際の作業', workers: [_workerInput()]);
    expect(((fixture.requests.single['p_workers'] as List).single as Map).length, 6);
    expect(fixture.calls, ['save_shared_report_document_draft']);
  });
  test('finalize sends exact displayed CAS and verifies completed signed response', () async {
    final fixture = _RpcFixture()..explicit = true..complete = true;
    addTearDown(fixture.client.dispose); await fixture.login();
    final after = await fixture.repository.finalize(before: fixture.before(ready: true));
    expect(fixture.calls, ['finalize_shared_daily_report']);
    expect(fixture.requests.single, {'p_report_id': _report,
      'p_expected_updated_at': _stamp.toIso8601String(), 'p_expected_signature_scope': _scope});
    expect(after.explicitFinalizationCompleted, isTrue);
  });
  const visit = RouteVisitReportContext(sourceClockInId: _source, routeAssignmentId: 'route',
    routeStopId: 'stop', startCaptureId: 'arrival', endCaptureId: 'move');
  for (final switchAba in [false, true]) {
    test('visit finalize pins displayed scope and rejects in-flight account history: $switchAba', () async {
      final fixture = _RpcFixture()..route = true;
      addTearDown(fixture.client.dispose); await fixture.login();
      final repository = DailyReportRepository.forTesting(fixture.client);
      final before = (await repository.loadVisitReport(visit))!;
      expect(before.signed, isFalse); expect(before.canFinalizeVisit, isTrue);
      fixture.complete = true; fixture.switchAba = switchAba;
      if (switchAba) {
        await expectLater(repository.finalizeVisit(context: visit, before: before), throwsA(isA<DailyReportActorChanged>()));
      } else {
        expect((await repository.finalizeVisit(context: visit, before: before)).signed, isTrue);
      }
      expect(fixture.calls, ['read_route_visit_report', 'finalize_route_visit_report']);
      expect(fixture.requests.last, {'p_report_id': _report,
        'p_expected_updated_at': _stamp.toIso8601String(), 'p_expected_signature_scope': _scope});
    });
  }

}

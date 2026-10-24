import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sk_works/features/daily_reports/daily_report_repository.dart';
import 'package:sk_works/features/daily_reports/daily_report_company_allowance_selection.dart';
import 'package:sk_works/features/shared/company_allowance_label_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _actor = '20000000-0000-0000-0000-000000000001';
const _other = '20000000-0000-0000-0000-000000000002';

String _session(String id, {int mark = 0}) {
  String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return jsonEncode({'access_token': '${part({'alg': 'HS256'})}.${part({
    'sub': id, 'exp': now + 3600, 'fixture': mark})}.synthetic',
    'refresh_token': 'synthetic', 'token_type': 'bearer', 'expires_in': 3600,
    'user': {'id': id, 'aud': 'authenticated', 'created_at': '2026-01-01T00:00:00Z',
      'app_metadata': {}, 'user_metadata': {}, 'identities': []}});
}

class _Labels implements CompanyAllowanceLabelSource {
  final companies = <String>[];
  String? returnedCompany;
  Completer<void>? started, release;
  @override
  Future<CompanyAllowanceLabelSnapshot> read(String companyId) async {
    companies.add(companyId);
    started?.complete();
    await release?.future;
    return CompanyAllowanceLabelSnapshot(companyId: returnedCompany ?? companyId,
      version: 1, items: const [CompanyAllowanceLabel(
        id: '10000000-0000-0000-0000-000000000001', name: 'PC手当', unit: 'day', generation: 1, registrationVersion: 1)]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SupabaseClient client;
  late MockClient network;
  late _Labels labels;
  late DailyReportRepository repository;
  late List<http.Request> requests;
  var rows = <Map<String, Object?>>[];
  var capability = true;
  Object? echoedSelections;
  List<Map<String, Object?>>? reportRows;
  setUp(() async {
    rows = [{'id': 'one', 'company_id': 'own'}, {'id': 'two', 'company_id': 'own'}];
    requests = []; capability = true; echoedSelections = null; reportRows = null;
    network = MockClient((request) async {
      requests.add(request);
      Object? result;
      if (request.url.path.endsWith('/company_checkout_allowance_contract_version')) {
        result = capability ? 1 : 0;
      } else if (request.url.path.endsWith('/read_daily_report_company_allowance_eligibility')) {
        expect(jsonDecode(request.body), {'p_report_id': 'report'});
        result = {'contract_version': 1, 'report_id': 'report', 'company_id': 'own',
          'source_versions': {'legacy_version': null, 'common_version': 1},
          'workers': [{'worker_id': 'one', 'items': [{'origin': 'company_legacy',
            'id': '10000000-0000-0000-0000-000000000001', 'generation': 1, 'registration_version': 1}]}]};
      } else if (request.url.path == '/rest/v1/workers') {
        expect(request.method, 'GET');
        expect(request.url.queryParameters['select'], 'id,company_id');
        expect(request.url.queryParameters['id'], 'in.("one","two")');
        result = rows;
      } else if (request.url.path.endsWith('/save_daily_report_destination_draft')) {
        result = 'report';
      } else if (request.url.path == '/rest/v1/daily_report_workers') {
        expect(request.url.queryParameters['report_id'], 'eq.report');
        result = [{'worker_id': 'one', 'company_allowance_selections': echoedSelections}];
      } else if (request.url.path == '/rest/v1/daily_reports') {
        final selection = request.url.queryParameters['select'] ?? '';
        expect(selection.contains('company_allowance_selections'), capability);
        result = reportRows ?? [];
      } else if (request.url.path.endsWith('/get_attendance_rollout_capabilities')) {
        result = {};
      } else if (request.url.path.endsWith('/save_daily_report_vehicle_usage') ||
          request.url.path.endsWith('/link_daily_report_attendance_evidence')) {
        result = null;
      } else { throw StateError('Unexpected fixture route: ${request.url.path}'); }
      return http.Response(jsonEncode(result), 200, request: request,
        headers: {'content-type': 'application/json'});
    });
    client = SupabaseClient('https://report.invalid', 'synthetic-public',
      authOptions: const AuthClientOptions(autoRefreshToken: false), httpClient: network);
    await client.auth.setInitialSession(_session(_actor));
    labels = _Labels();
    repository = DailyReportRepository.forTesting(client, companyAllowanceLabels: labels);
  });
  tearDown(() async { await client.dispose(); network.close(); });

  test('saved-report eligibility binds exact worker identities without salary data', () async {
    final snapshot = await labels.read('own');
    final allowed = await repository.loadCompanyAllowanceEligibility(reportId: 'report',
      workerIds: ['one'], snapshot: snapshot);
    expect(allowed['one'], {'company_legacy/10000000-0000-0000-0000-000000000001'});
    final request = requests.single;
    expect(request.headers['authorization'], 'Bearer ${client.auth.currentSession!.accessToken}');
    expect(request.url.path, '/rest/v1/rpc/read_daily_report_company_allowance_eligibility');
  });

  test('selected roster resolves one explicit company before names-only read', () async {
    final token = client.auth.currentSession!.accessToken;
    final snapshot = await repository.loadCompanyAllowanceLabels(
      workerIds: ['two', 'one'], expectedCompanyId: 'own');
    expect(snapshot.items.single.name, 'PC手当');
    expect(labels.companies, ['own']);
    expect(requests.singleWhere((r) => r.url.path == '/rest/v1/workers').headers['authorization'], 'Bearer $token');
    expect(client.auth.currentSession!.accessToken, token);
  });

  test('partial, mixed or wrong-company roster never requests registered names', () async {
    for (final invalid in [
      [{'id': 'one', 'company_id': 'own'}],
      [{'id': 'one', 'company_id': 'own'}, {'id': 'two', 'company_id': 'other'}],
      [{'id': 'one', 'company_id': 'other'}, {'id': 'two', 'company_id': 'other'}],
    ]) {
      rows = invalid;
      await expectLater(repository.loadCompanyAllowanceLabels(
        workerIds: ['one', 'two'], expectedCompanyId: 'own'), throwsStateError);
    }
    expect(labels.companies, isEmpty);
  });

  test('different company response cannot become report choices', () async {
    labels.returnedCompany = 'other';
    await expectLater(repository.loadCompanyAllowanceLabels(
      workerIds: ['one', 'two'], expectedCompanyId: 'own'), throwsStateError);
  });

  test('actor or token change while reading labels rejects stale choices', () async {
    for (final id in [_other, _actor]) {
      await client.auth.setInitialSession(_session(_actor));
      labels.started = Completer<void>(); labels.release = Completer<void>();
      final pending = repository.loadCompanyAllowanceLabels(
        workerIds: ['one', 'two'], expectedCompanyId: 'own');
      final assertion = expectLater(pending, throwsA(isA<DailyReportActorChanged>()));
      await labels.started!.future;
      await client.auth.setInitialSession(_session(id, mark: 1));
      labels.release!.complete();
      await assertion;
    }
  });
  DailyReportCompanyAllowanceSelections choice() => DailyReportCompanyAllowanceSelections([
    DailyReportCompanyAllowanceSelection.fromJson({
      'origin': 'company_legacy', 'id': '10000000-0000-0000-0000-000000000001',
      'generation': 1, 'registration_version': 7, 'name_snapshot': 'PC手当', 'unit': 'day'})]);

  test('new selection is not sent when the payroll handoff contract is unavailable', () async {
    capability = false;
    await expectLater(repository.saveDraft(siteId: 'site', date: DateTime(2026, 10, 1),
      workDescription: '合成', workers: [DailyReportWorkerDraft(workerId: 'one', workerName: '合成社員',
        allowanceLabel: 'PC手当', companyAllowanceSelections: choice())]), throwsStateError);
    expect(requests.any((r) => r.url.path.endsWith('/save_daily_report_destination_draft')), isFalse);
  });

  test('typed save checks exact metadata echo before normal post-save linking', () async {
    final selected = choice(); echoedSelections = selected.toJson();
    final worker = DailyReportWorkerDraft(workerId: 'one', workerName: '合成社員',
      allowanceLabel: 'PC手当', companyAllowanceSelections: selected);
    expect(await repository.saveDraft(siteId: 'site', date: DateTime(2026, 10, 1),
      workDescription: '合成', workers: [worker]), 'report');
    final write = requests.singleWhere((r) => r.url.path.endsWith('/save_daily_report_destination_draft'));
    final payload = (jsonDecode(write.body) as Map)['p_workers'] as List;
    expect((payload.single as Map)['company_allowance_selections'], selected.toJson());
    expect((payload.single as Map)['allowance_amount'], 0);
    final read = requests.indexWhere((r) => r.url.path == '/rest/v1/daily_report_workers');
    final link = requests.indexWhere((r) => r.url.path.endsWith('/link_daily_report_attendance_evidence'));
    expect(read, greaterThanOrEqualTo(0)); expect(link, greaterThan(read));
  });

  test('silently dropped or changed metadata cannot report typed saving successful', () async {
    final selected = choice();
    final worker = DailyReportWorkerDraft(workerId: 'one', workerName: '合成社員',
      allowanceLabel: 'PC手当', companyAllowanceSelections: selected);
    await expectLater(repository.saveDraft(siteId: 'site', date: DateTime(2026, 10, 1),
      workDescription: '合成', workers: [worker]), throwsFormatException);
    expect(requests.any((r) => r.url.path.endsWith('/link_daily_report_attendance_evidence')), isFalse);
    echoedSelections = {'contract_version': 1, 'items': []}; requests.clear();
    await expectLater(repository.saveDraft(siteId: 'site', date: DateTime(2026, 10, 1),
      workDescription: '合成', workers: [worker]), throwsStateError);
    expect(requests.any((r) => r.url.path.endsWith('/link_daily_report_attendance_evidence')), isFalse);
  });

  test('normal report load selects typed metadata only with server capability', () async {
    final selected = choice();
    reportRows = [{'id': 'report', 'company_id': 'own', 'site_id': 'site',
      'report_date': '2026-10-01', 'status': 'draft', 'work_description': '',
      'daily_report_workers': [{'worker_id': 'one', 'workers': {'name': '合成社員'},
        'allowance_label': 'PC手当', 'company_allowance_selections': selected.toJson()}]}];
    final saved = await repository.loadReport(date: DateTime(2026, 10, 1), siteId: 'site');
    expect(saved!.workers.single.companyAllowanceSelections!.toJson(), selected.toJson());
    capability = false; reportRows = [];
    expect(await repository.loadReport(date: DateTime(2026, 10, 1), siteId: 'site'), isNull);
  });

}

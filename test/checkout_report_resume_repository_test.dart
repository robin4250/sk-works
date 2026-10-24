import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/attendance/checkout_report_resume_repository.dart';

const company = '00000000-0000-0000-0000-000000000001';
const worker = '00000000-0000-0000-0000-000000000002';
const actorId = '00000000-0000-0000-0000-000000000003';
const site = '00000000-0000-0000-0000-000000000004';
String id(int n) => '00000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';
const signature = {'strokes': [[{'x': 0.1, 'y': 0.1}]]};

class _Fixture {
  String actor = actorId, role = 'owner', workerUser = actorId;
  bool forceReport = false, reporter = false, responsible = false, signed = false,
      formal = false, frozen = false, failRead = false, actorChange = false,
      badPair = false, duplicateEnd = false, otherCompany = false, rosterMissing = false;
  final requests = <http.Request>[];
  late final client = SupabaseClient('https://synthetic.invalid', 'fixture-only',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient(_respond));
  CheckoutReportResumeRepository get repository =>
      CheckoutReportResumeRepository.forTesting(client, () => actor);

  Future<http.Response> _respond(http.Request request) async {
    requests.add(request);
    expect(request.method, 'GET', reason: 'Resuming a report must not create clocks, reports or money');
    final path = request.url.path.split('/').last;
    final rawDay = request.url.queryParameters['work_date'] ??
        request.url.queryParameters['report_date'] ?? 'eq.2026-10-21';
    final reportFilter = request.url.queryParameters['report_id'];
    final day = reportFilter == null
        ? int.parse(rawDay.substring(rawDay.length - 2))
        : int.parse(reportFilter.substring(reportFilter.length - 12)) - 200;
    final text = '2026-10-${day.toString().padLeft(2, '0')}';
    final completed = [12, 16].contains(day);
    final reportExists = completed || forceReport;
    final rid = id(200 + day);
    Object rows = <Object>[];
    switch (path) {
      case 'workers':
        rows = [{'id': worker, 'company_id': otherCompany ? id(99) : company, 'user_id': workerUser}];
      case 'company_members':
        rows = [{'company_id': company, 'user_id': actorId, 'role': role}];
      case 'member_feature_permissions':
        rows = [{'company_id': company, 'user_id': actorId, 'can_manage_attendance': false}];
      case 'attendance_verifications':
        if (failRead) { return http.Response('{"message":"fixture read failed","code":"42501"}',403,
            headers: {'content-type':'application/json'}, request: request); }
        final start = {'id': id(1000+day), 'company_id': company, 'worker_id': worker,
          'work_date': text, 'event_type': 'clock_in', 'confirmed_at': '${text}T08:00:00+09:00',
          'source_clock_in_id': null, 'site_id': site, 'route_assignment_id': null,
          'daily_report_id': reportExists ? rid : null, 'sites': {'name':'合成現場'}};
        final end = {...start, 'id': id(1100+day), 'event_type':'clock_out',
          'source_clock_in_id': badPair ? id(9999) : id(1000+day),
          'confirmed_at': day == 21 ? '2026-10-22T01:00:00+09:00' : '${text}T17:00:00+09:00'};
        rows = [start,end,if(duplicateEnd) {...end,'id':id(1200+day)}];
        if(actorChange) { actor=id(98); }
      case 'daily_reports':
        rows = reportExists ? [{'id':rid, 'company_id':company, 'report_date':text,
          'site_id':site, 'route_assignment_id':null, 'status':completed || signed ? 'signed':'draft',
          'representative_signer_name':completed || reporter ? '合成報告者':null,
          'supervisor_signer_name':completed || responsible ? '合成責任者':null,
          'representative_signature_json':completed || reporter ? signature:null,
          'supervisor_signature_json':completed || responsible ? signature:null}] : <Object>[];
      case 'daily_report_workers':
        rows = rosterMissing ? <Object>[] : [{'report_id':rid,'worker_id':worker}];
      case 'attendance_entries':
        rows = completed || formal ? [{'id':id(300+day),'company_id':company,'worker_id':worker,
          'work_date':text,'site_id':site,'route_assignment_id':null,'source_report_id':rid,'base_man_days':1}] : <Object>[];
      case 'payroll_statements':
        rows = [{'company_id':company,'worker_id':worker,'period_start':'2026-10-01',
          'workflow_state':frozen?'approved':'draft','automatic_calculation':true,
          'finalized_at':frozen?'2026-10-25T00:00:00Z':null}];
      default: throw StateError('Unexpected path $path');
    }
    return http.Response(jsonEncode(rows),200,headers:{'content-type':'application/json'}, request: request);
  }
}

void main() {
  late _Fixture fixture;
  setUp(() => fixture = _Fixture());
  tearDown(() async => fixture.client.dispose().timeout(const Duration(seconds: 2)));
  test('five exact closed days resolve two complete reports and three resumable missing reports', () async {
    final results=<CheckoutReportResumeTarget>[];
    for(final day in [12,16,21,22,24]){
      final rows=await fixture.repository.loadDay(workerId:worker,workDate:DateTime(2026,10,day));
      expect(rows.length,1); results.add(rows.single);
    }
    expect(results.where((row)=>row.complete).length,2);
    expect(results.where((row)=>row.state==CheckoutReportState.missing).map((row)=>row.workDate.day),[21,22,24]);
    expect(results[2].workDate,DateTime(2026,10,21));
    expect(fixture.requests.every((request)=>request.method=='GET'),true);
  });
  test('stored reporter signature is separate from salary completion and responsibility may remain pending', () async {
    fixture.forceReport=true;fixture.reporter=true;
    final row=(await fixture.repository.loadDay(workerId:worker,workDate:DateTime(2026,10,24))).single;
    expect(row.state,CheckoutReportState.partialSignature);
    expect(row.reporterSignatureSaved,true);
    expect(row.responsibleSignatureSaved,false);
    expect(row.complete,false);
  });
  test('two signed roles without formal attendance are not called financial completion', () async {
    fixture.forceReport=true;fixture.reporter=true;fixture.responsible=true;fixture.signed=true;
    final row=(await fixture.repository.loadDay(workerId:worker,workDate:DateTime(2026,10,24))).single;
    expect(row.state,CheckoutReportState.signedWithoutAttendance);
    expect(row.complete,false);
  });
  test('signed same-day existing report and formal attendance are reused rather than recreated', () async {
    fixture.forceReport=true;fixture.reporter=true;fixture.responsible=true;fixture.signed=true;fixture.formal=true;
    final row=(await fixture.repository.loadDay(workerId:worker,workDate:DateTime(2026,10,24))).single;
    expect(row.state,CheckoutReportState.complete);
    expect(row.reportId,id(224));
    expect(fixture.requests.every((request)=>request.method=='GET'),true);
  });
  test('protected payroll period does not offer creating an unapproved historical attendance', () async {
    fixture.frozen=true;
    final row=(await fixture.repository.loadDay(workerId:worker,workDate:DateTime(2026,10,24))).single;
    expect(row.state,CheckoutReportState.protectedPeriod);expect(row.needsCompletion,false);
  });
  for(final bad in ['pair','duplicate','actor','company','denied','roster','read']){
    test('scope safety $bad never becomes a newly created report',() async {
      if(bad=='pair') { fixture.badPair=true; }
      if(bad=='duplicate') { fixture.duplicateEnd=true; }
      if(bad=='actor') { fixture.actorChange=true; }
      if(bad=='company') { fixture.otherCompany=true; }
      if(bad=='denied'){fixture.workerUser=id(77);fixture.role='viewer';}
      if(bad=='roster'){fixture.forceReport=true;fixture.reporter=true;fixture.rosterMissing=true;}
      if(bad=='read') { fixture.failRead=true; }
      if(bad=='roster'){
        final row=(await fixture.repository.loadDay(workerId:worker,workDate:DateTime(2026,10,24))).single;
        expect(row.state,CheckoutReportState.conflict);expect(row.reporterSignatureSaved,false);
      }else{
        await expectLater(fixture.repository.loadDay(workerId:worker,workDate:DateTime(2026,10,24)),throwsA(anyOf(isA<StateError>(), isA<PostgrestException>())));
      }
      expect(fixture.requests.every((request)=>request.method=='GET'),true);
    });
  }
}

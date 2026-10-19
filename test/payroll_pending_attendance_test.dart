import 'dart:convert';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/attendance/attendance_management_repository.dart';

const actor = '11111111-1111-1111-1111-111111111111';
const company = '22222222-2222-2222-2222-222222222222';
const worker = '33333333-3333-3333-3333-333333333333';
const site = '44444444-4444-4444-4444-444444444444';

class PayrollFixture {
  bool draft = true;
  Completer<void>? entriesGate;
  final calls = <http.Request>[];
  bool recorded = false;
  bool leave = false;
  bool allowed = true;
  List<Map<String, dynamic>> punches = [
    {
      'work_date': '2026-10-13',
      'event_type': 'clock_in',
      'confirmed_at': '2026-10-13T08:13:00Z',
      'site_id': site,
    },
    {
      'work_date': '2026-10-13',
      'event_type': 'clock_out',
      'confirmed_at': '2026-10-13T17:21:00Z',
      'site_id': site,
    },
  ];
  late SupabaseClient client;
  late AttendanceManagementRepository repository;
  Future<void> start() async {
    client = SupabaseClient(
      'https://attendance-fixture.invalid',
      'synthetic',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        calls.add(request);
        Object? body;
        switch (request.url.path) {
          case '/auth/v1/logout':
            body = <String,dynamic>{};
          case '/auth/v1/token':
            String enc(Object value) => base64Url
                .encode(utf8.encode(jsonEncode(value)))
                .replaceAll('=', '');
            body = {
              'access_token':
                  '${enc({'alg': 'HS256'})}.${enc({'sub': actor, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.c3ludGhldGlj',
              'refresh_token': 'synthetic',
              'token_type': 'bearer',
              'expires_in': 3600,
              'user': {
                'id': actor,
                'aud': 'authenticated',
                'role': 'authenticated',
                'created_at': '2026-01-01T00:00:00Z',
              },
            };
          case '/rest/v1/company_members':
            body = [
              {'company_id': company, 'role': 'owner'},
            ];
          case '/rest/v1/rpc/current_feature_permissions':
            body = {'can_manage_attendance': allowed};
          case '/rest/v1/workers':
            body = [
              {'id': worker, 'name': '検証社員'},
            ];
          case '/rest/v1/sites':
            body = [
              {'id': site, 'name': '検証現場'},
            ];
          case '/rest/v1/payroll_statements':
            body = {'id': 'statement', 'company_id': company, 'worker_id': worker, 'period_start': '2026-10-01', 'workflow_state': draft ? 'draft' : 'finalized'};
          case '/rest/v1/attendance_entries':
            await entriesGate?.future;
            body = recorded
                ? [
                    {'work_date': '2026-10-12'}, {'work_date': '2026-10-16'},
                  ]
                : [];
          case '/rest/v1/paid_leave_requests':
            body = leave
                ? [
                    {'leave_date': '2026-10-13'},
                  ]
                : [];
          case '/rest/v1/attendance_verifications':
            body = punches;
          default:
            throw StateError(
              'Unexpected ${request.method} ${request.url.path}',
            );
        }
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    await client.auth.signInWithPassword(
      email: 'fixture@example.invalid',
      password: 'synthetic',
    );
    calls.clear();
    repository = AttendanceManagementRepository.forTesting(client);
  }
}


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('same worker and month: two recorded days and duplicate punch-only day produce one pending day without writes', () async {
    final f = PayrollFixture(); await f.start(); addTearDown(f.client.dispose);
    f.recorded = true;
    f.punches.addAll([
      {'work_date': '2026-10-12', 'event_type': 'clock_in', 'confirmed_at': '2026-10-12T08:00:00Z'},
      {'work_date': '2026-10-16', 'event_type': 'clock_out', 'confirmed_at': '2026-10-16T18:00:00Z'},
      {'work_date': '2026-09-30', 'event_type': 'clock_in', 'confirmed_at': '2026-10-13T08:00:00Z'},
      {'work_date': '2026-10-14', 'event_type': 'other', 'confirmed_at': '2026-10-14T08:00:00Z'},
    ]);
    final result = await f.repository.loadPayrollPendingDays('statement');
    expect(result!.workerId, worker);
    expect(result.dates, [DateTime(2026,10,13)]);
    for (final r in f.calls.where((r) => const {'attendance_entries','attendance_verifications','paid_leave_requests'}.contains(r.url.path.split('/').last))) {
      expect(r.method, 'GET');
      expect(r.url.queryParameters['company_id'], 'eq.$company');
      expect(r.url.queryParameters['worker_id'], 'eq.$worker');
    }
    expect(f.calls.every((r) => r.method == 'GET' || r.url.path.endsWith('/current_feature_permissions')), isTrue);
    final entries = f.calls.firstWhere((r) => r.url.path.endsWith('/attendance_entries'));
    expect(entries.url.queryParametersAll['work_date'], containsAll(['gte.2026-10-01', 'lt.2026-11-01']));
    expect(entries.url.query, contains('gte.2026-10-01'));
  });
  test('approved leave is not an unconfirmed work day; finalized payroll is not queried for gaps', () async {
    final f = PayrollFixture(); await f.start(); addTearDown(f.client.dispose);
    f.leave = true;
    expect((await f.repository.loadPayrollPendingDays('statement'))!.dates, isEmpty);
    f.calls.clear(); f.draft = false;
    expect(await f.repository.loadPayrollPendingDays('statement'), isNull);
    expect(f.calls.any((r) => r.url.path.endsWith('/attendance_entries')), isFalse);
  });
  test('attendance permission denied never reads payroll or attendance', () async {
    final f = PayrollFixture(); await f.start(); addTearDown(f.client.dispose); f.allowed = false;
    expect(await f.repository.loadPayrollPendingDays('statement'), isNull);
    expect(f.calls.any((r) => r.url.path.endsWith('/payroll_statements')), isFalse);
    expect(f.calls.any((r) => r.url.path.endsWith('/attendance_verifications')), isFalse);
  });
  test('logout during reading refuses late data and stops further reads', () async {
    final f = PayrollFixture(); await f.start(); addTearDown(f.client.dispose);
    f.entriesGate = Completer<void>();
    final reading = f.repository.loadPayrollPendingDays('statement');
    final expectation = expectLater(reading, throwsStateError);
    while (!f.calls.any((r) => r.url.path.endsWith('/attendance_entries'))) { await Future<void>.delayed(Duration.zero); }
    await f.client.auth.signOut(scope: SignOutScope.local);
    f.entriesGate!.complete(); await expectation;
    expect(f.calls.any((r) => r.url.path.endsWith('/attendance_verifications')), isFalse);
  });
}

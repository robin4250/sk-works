import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/attendance/worker_attendance_sheet_repository.dart';

String id(int n) => '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
Map<String, dynamic> session(int sid) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return {
    'access_token':
        '${part({'alg': 'HS256'})}.${part({'sub': id(1), 'session_id': id(sid), 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.synthetic',
    'refresh_token': 'synthetic',
    'expires_in': 3600,
    'token_type': 'bearer',
    'user': {
      'id': id(1),
      'aud': 'authenticated',
      'created_at': '2026-01-01T00:00:00Z',
    },
  };
}

void main() {
  test(
    'partner month reads the same scoped NULL-source attendance ID without writes or payroll RPC',
    () async {
      final methods = <String>[];
      final wire = MockClient((request) async {
        methods.add(request.method);
        final path = request.url.path;
        Object body;
        if (path.endsWith('company_members')) {
          body = [
            {'company_id': id(2)},
          ];
        } else if (path.endsWith('workers')) {
          expect(request.url.queryParameters['company_id'], 'eq.${id(2)}');
          body = [
            {
              'id': id(3),
              'name': '同名作業者',
              'company_id': id(2),
              'affiliation': 'partner_company',
              'status': 'active',
              'partner_company_id': id(4),
              'partner_companies': {
                'id': id(4),
                'name': '合成協力会社',
                'company_id': id(2),
              },
            },
          ];
        } else {
          expect(path, '/rest/v1/attendance_entries');
          expect(request.url.queryParameters['worker_id'], 'eq.${id(3)}');
          expect(request.url.queryParameters['company_id'], 'eq.${id(2)}');
          body = [
            {
              'id': id(5),
              'company_id': id(2),
              'worker_id': id(3),
              'site_id': id(6),
              'sites': {'id': id(6), 'name': '合成現場', 'company_id': id(2)},
              'source_report_id': null,
              'work_date': '2026-11-02',
              'base_man_days': 1,
              'overtime_hours': 2,
              'early_hours': 0,
              'night_hours': 0,
            },
          ];
        }
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      });
      final client = SupabaseClient(
        'https://fixture.invalid',
        'synthetic',
        httpClient: wire,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      await client.auth.setInitialSession(jsonEncode(session(7)));
      addTearDown(client.dispose);
      final repo = WorkerAttendanceSheetRepository.forClient(client);
      final workers = await repo.loadPartnerWorkers();
      expect(workers.single.partnerName, '合成協力会社');
      final rows = await repo.loadPartnerAttendanceMonth(
        workers.single,
        DateTime(2026, 11),
      );
      expect(rows.single['id'], id(5));
      expect(rows.single['source_report_id'], isNull);
      expect(methods.every((method) => method == 'GET'), isTrue);
    },
  );

  test('ambiguous membership fails before any partner query', () async {
    var workerCalls = 0;
    final client = SupabaseClient(
      'https://fixture.invalid',
      'synthetic',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('workers')) workerCalls++;
        return http.Response(
          jsonEncode([
            {'company_id': id(2)},
            {'company_id': id(8)},
          ]),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    await client.auth.setInitialSession(jsonEncode(session(7)));
    addTearDown(client.dispose);
    await expectLater(
      WorkerAttendanceSheetRepository.forClient(client).loadPartnerWorkers(),
      throwsStateError,
    );
    expect(workerCalls, 0);
  });

  test('old worker/session binding is rejected before month read', () async {
    var calls = 0;
    final client = SupabaseClient(
      'https://fixture.invalid',
      'synthetic',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        calls++;
        return http.Response(
          '[]',
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    await client.auth.setInitialSession(jsonEncode(session(9)));
    addTearDown(client.dispose);
    final worker = PartnerAttendanceWorker(
      id: id(3),
      name: '同名',
      companyId: id(2),
      partnerId: id(4),
      partnerName: '合成会社',
      actorSession: '${id(1)}/${id(7)}',
    );
    await expectLater(
      WorkerAttendanceSheetRepository.forClient(
        client,
      ).loadPartnerAttendanceMonth(worker, DateTime(2026, 11)),
      throwsStateError,
    );
    expect(calls, 0);
  });
  test(
    'pending read stays on captured bearer and is discarded after SID change',
    () async {
      final entered = Completer<void>();
      final resume = Completer<void>();
      final headers = <String>[];
      final client = await partnerClient((request) async {
        headers.add(request.headers['authorization'] ?? '');
        if (request.url.path.endsWith('company_members')) {
          return http.Response(
            jsonEncode([
              {'company_id': id(2)},
            ]),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        entered.complete();
        await resume.future;
        return http.Response(
          jsonEncode([
            {
              'id': id(3),
              'name': '合成',
              'company_id': id(2),
              'affiliation': 'partner_company',
              'status': 'active',
              'partner_company_id': id(4),
              'partner_companies': {
                'id': id(4),
                'name': '合成会社',
                'company_id': id(2),
              },
            },
          ]),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      });
      addTearDown(client.dispose);
      final oldBearer = client.auth.currentSession!.accessToken;
      final future = WorkerAttendanceSheetRepository.forClient(
        client,
      ).loadPartnerWorkers();
      final assertion = expectLater(future, throwsStateError);
      await entered.future;
      await client.auth.recoverSession(jsonEncode(session(9)));
      resume.complete();
      await assertion;
      expect(headers.every((header) => header == 'Bearer $oldBearer'), isTrue);
    },
  );

  test(
    'month response must remain in the requested month and exact worker scope',
    () async {
      for (final invalid in ['month', 'foreign', 'partner']) {
        final client = await partnerClient((request) async {
          Object body;
          if (request.url.path.endsWith('company_members')) {
            body = [
              {'company_id': id(2)},
            ];
          } else if (request.url.path.endsWith('workers')) {
            body = [
              {
                'id': id(3),
                'company_id': id(2),
                'partner_company_id': invalid == 'partner' ? id(99) : id(4),
                'affiliation': 'partner_company',
                'status': 'active',
              },
            ];
          } else {
            body = [
              {
                'id': id(5),
                'company_id': invalid == 'foreign' ? id(99) : id(2),
                'worker_id': id(3),
                'site_id': id(6),
                'route_assignment_id': null,
                'sites': {'id': id(6), 'name': '合成現場', 'company_id': id(2)},
                'source_report_id': null,
                'work_date': invalid == 'month' ? '2026-12-01' : '2026-11-02',
                'base_man_days': 1,
                'overtime_hours': 0,
                'early_hours': 0,
                'night_hours': 0,
              },
            ];
          }
          return http.Response(
            jsonEncode(body),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        });
        final worker = PartnerAttendanceWorker(
          id: id(3),
          name: '同名',
          companyId: id(2),
          partnerId: id(4),
          partnerName: '合成会社',
          actorSession: '${id(1)}/${id(7)}',
        );
        await expectLater(
          WorkerAttendanceSheetRepository.forClient(
            client,
          ).loadPartnerAttendanceMonth(worker, DateTime(2026, 11)),
          throwsStateError,
        );
        await client.dispose();
      }
    },
  );
}

Future<SupabaseClient> partnerClient(
  Future<http.Response> Function(http.Request) handler,
) async {
  final client = SupabaseClient(
    'https://fixture.invalid',
    'synthetic',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient(handler),
  );
  await client.auth.setInitialSession(jsonEncode(session(7)));
  return client;
}

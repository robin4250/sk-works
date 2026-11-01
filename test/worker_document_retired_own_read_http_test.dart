import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/people/worker_document_repository.dart';

const actor = '10000000-0000-0000-0000-000000000001';
const otherActor = '10000000-0000-0000-0000-000000000002';
const company = '20000000-0000-0000-0000-000000000001';
const otherCompany = '20000000-0000-0000-0000-000000000002';
const worker = '30000000-0000-0000-0000-000000000001';
const otherWorker = '30000000-0000-0000-0000-000000000002';
const requirement = '40000000-0000-0000-0000-000000000001';
const statusId = '50000000-0000-0000-0000-000000000001';

Map<String, dynamic> session(String sid) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return {
    'access_token':
        '${part({'alg': 'HS256'})}.${part({'sub': actor, 'session_id': sid, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.synthetic',
    'refresh_token': 'synthetic-$sid',
    'token_type': 'bearer',
    'expires_in': 3600,
    'user': {
      'id': actor,
      'aud': 'authenticated',
      'created_at': '2026-11-01T00:00:00Z',
      'app_metadata': <String, dynamic>{},
      'user_metadata': <String, dynamic>{},
    },
  };
}

class Fixture {
  late SupabaseClient client;
  late WorkerDocumentRepository repository;
  final requests = <http.Request>[];
  List<Map<String, dynamic>> memberships = [
    {'company_id': company, 'role': 'viewer'},
  ];
  List<Map<String, dynamic>> workers = [
    {
      'id': worker,
      'company_id': company,
      'user_id': actor,
      'name': 'Synthetic retired worker',
      'affiliation': 'employee',
      'status': 'inactive',
    },
  ];
  List<Map<String, dynamic>> requirements = [
    {
      'id': requirement,
      'company_id': company,
      'name': '銀行口座情報',
      'is_active': true,
      'archived_at': null,
      'is_required': true,
    },
  ];
  List<Map<String, dynamic>> statuses = [
    {
      'id': statusId,
      'company_id': company,
      'worker_id': worker,
      'requirement_id': requirement,
      'status': 'submitted',
      'attachment_path': '$company/$worker/synthetic-original.jpg',
      'attachment_paths': ['$company/$worker/synthetic-original.jpg'],
    },
  ];
  bool missingPhotoColumn = false;
  int photoReads = 0;
  String? waitPath;
  Completer<void>? wait;
  final started = Completer<void>();
  Future<void> login(String sid) =>
      client.auth.setInitialSession(jsonEncode(session(sid)));
  static Future<Fixture> create() async {
    final f = Fixture();
    f.client = SupabaseClient(
      'https://retired-own-read.synthetic.invalid',
      'synthetic-public',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((r) async {
        f.requests.add(r);
        final path = r.url.path.split('/').last;
        if (path == f.waitPath && f.wait != null) {
          if (!f.started.isCompleted) f.started.complete();
          await f.wait!.future;
        }
        Object? value;
        var code = 200;
        switch (path) {
          case 'company_members':
            value = f.memberships;
          case 'workers':
            value = f.workers;
          case 'worker_document_exemption':
            value = {'capability_version': 1, 'can_manage': false, 'items': []};
          case 'document_requirements':
            value = f.requirements;
          case 'worker_document_statuses':
            f.photoReads++;
            if (f.missingPhotoColumn && f.photoReads == 1) {
              code = 400;
              value = {
                'code': '42703',
                'message': 'column attachment_paths does not exist',
              };
            } else {
              value = f.statuses;
            }
          case 'worker_private_bank_accounts':
            value = [];
          default:
            throw StateError('Unexpected endpoint: $path');
        }
        return http.Response(jsonEncode(value), code,
            headers: {'content-type': 'application/json'}, request: r);
      }),
    );
    await f.login('sid-a');
    f.repository = WorkerDocumentRepository.forTesting(f.client);
    return f;
  }

  Future<void> close() => client.dispose();
}

void main() {
  test('inactive own saved documents use only identity-bound reads, no initializer or bank proof', () async {
    final f = await Fixture.create();
    addTearDown(f.close);
    final bearer = 'Bearer ${f.client.auth.currentSession!.accessToken}';
    final saved = jsonEncode(f.statuses);
    final value = await f.repository.loadAll();
    expect(value['workers']!.single['status'], 'inactive');
    expect(value['workers']!.single.containsKey('user_id'), false);
    expect(jsonEncode(value['statuses']), saved);
    expect(value['bank_account_metadata'], isEmpty);
    for (final r in f.requests.where((r) => r.url.path.endsWith('/workers'))) {
      expect(r.url.queryParameters['company_id'], 'eq.$company');
      expect(r.url.queryParameters['user_id'], 'eq.$actor');
      expect(r.url.queryParameters['limit'], '2');
      expect(r.url.queryParameters['status'],
          anyOf('in.(active,inactive)', 'in.("active","inactive")'));
    }
    final statusRead = f.requests.singleWhere((r) => r.url.path.endsWith('/worker_document_statuses'));
    expect(statusRead.url.queryParameters['worker_id'], 'eq.$worker');
    expect(f.requests.every((r) => r.headers['Authorization'] == bearer), true);
    expect(f.requests.any((r) => r.url.path.contains('ensure_current_user_worker')), false);
    expect(f.requests.any((r) => r.url.path.endsWith('worker_private_bank_accounts')), false);
    expect(f.requests.where((r) => r.method != 'GET').map((r) => r.url.path.split('/').last), ['worker_document_exemption']);
    final exempt = jsonDecode(f.requests.singleWhere((r) => r.url.path.endsWith('worker_document_exemption')).body) as Map;
    expect(exempt['p_action'], 'list');
  });
  test('active own read retains the existing active bank reader', () async {
    final f = await Fixture.create();
    addTearDown(f.close);
    f.workers.single['status'] = 'active';
    final value = await f.repository.loadAll();
    expect(value['workers']!.single['status'], 'active');
    expect(f.requests.where((r) => r.url.path.endsWith('worker_private_bank_accounts')), hasLength(1));
  });
  test('manager roster remains active-only with no own inactive broadening', () async {
    final f = await Fixture.create();
    addTearDown(f.close);
    f.memberships.single['role'] = 'admin';
    f.workers.single['status'] = 'active';
    f.workers.single.remove('user_id');
    await f.repository.loadAll();
    final queries = f.requests.where((r) => r.url.path.endsWith('/workers'));
    expect(queries.every((r) => r.url.queryParameters['status'] == 'eq.active'), true);
    expect(queries.every((r) => !r.url.queryParameters.containsKey('user_id')), true);
  });
  for (final kind in ['empty', 'duplicate', 'foreign-company', 'foreign-person', 'invalid-id', 'unknown-status', 'null-status']) {
    test('own worker $kind fails before saved documents are read', () async {
      final f = await Fixture.create();
      addTearDown(f.close);
      switch (kind) {
        case 'empty': f.workers.clear();
        case 'duplicate': f.workers.add(Map.of(f.workers.single));
        case 'foreign-company': f.workers.single['company_id'] = otherCompany;
        case 'foreign-person': f.workers.single['user_id'] = otherActor;
        case 'invalid-id': f.workers.single['id'] = 'not-a-uuid';
        case 'unknown-status': f.workers.single['status'] = 'archived';
        case 'null-status': f.workers.single['status'] = null;
      }
      await expectLater(f.repository.loadAll(), throwsStateError);
      expect(f.requests.any((r) => r.url.path.endsWith('worker_document_statuses')), false);
    });
  }
  for (final kind in ['company', 'worker', 'id', 'requirement', 'duplicate-id', 'duplicate-requirement']) {
    test('saved status $kind mismatch is not returned', () async {
      final f = await Fixture.create();
      addTearDown(f.close);
      switch (kind) {
        case 'company': f.statuses.single['company_id'] = otherCompany;
        case 'worker': f.statuses.single['worker_id'] = otherWorker;
        case 'id': f.statuses.single['id'] = 'invalid';
        case 'requirement': f.statuses.single['requirement_id'] = 'invalid';
        case 'duplicate-id': f.statuses.add(Map.of(f.statuses.single));
        case 'duplicate-requirement': f.statuses.add({...f.statuses.single, 'id': '50000000-0000-0000-0000-000000000002'});
      }
      await expectLater(f.repository.loadAll(), throwsStateError);
    });
  }
  for (final kind in ['missing-role', 'unknown-role', 'company', 'duplicate']) {
    test('membership $kind cannot select an arbitrary worker', () async {
      final f = await Fixture.create();
      addTearDown(f.close);
      switch (kind) {
        case 'missing-role': f.memberships.single.remove('role');
        case 'unknown-role': f.memberships.single['role'] = 'unexpected';
        case 'company': f.memberships.single['company_id'] = 'invalid';
        case 'duplicate': f.memberships.add(Map.of(f.memberships.single));
      }
      await expectLater(f.repository.loadAll(), throwsStateError);
      expect(f.requests.any((r) => r.url.path.endsWith('/workers')), false);
    });
  }
  for (final kind in ['sid', 'sid-aba', 'company', 'role', 'worker-status']) {
    test('$kind change while statuses are pending discards the result', () async {
      final f = await Fixture.create();
      addTearDown(f.close);
      f.waitPath = 'worker_document_statuses';
      f.wait = Completer<void>();
      final pending = f.repository.loadAll();
      final rejected = expectLater(pending, throwsStateError);
      await f.started.future.timeout(const Duration(seconds: 5));
      switch (kind) {
        case 'sid': await f.login('sid-b');
        case 'sid-aba': await f.login('sid-b'); await f.login('sid-a');
        case 'company': f.memberships.single['company_id'] = otherCompany;
        case 'role': f.memberships.single['role'] = 'admin';
        case 'worker-status': f.workers.single['status'] = 'active';
      }
      f.wait!.complete();
      await rejected;
    });
  }
  test('missing photo column fallback retains captured identity and bearer', () async {
    final f = await Fixture.create();
    addTearDown(f.close);
    f.missingPhotoColumn = true;
    final bearer = 'Bearer ${f.client.auth.currentSession!.accessToken}';
    expect((await f.repository.loadAll())['statuses'], f.statuses);
    final reads = f.requests.where((r) => r.url.path.endsWith('/worker_document_statuses')).toList();
    expect(reads, hasLength(2));
    expect(reads.every((r) => r.headers['Authorization'] == bearer &&
        r.url.queryParameters['company_id'] == 'eq.$company' &&
        r.url.queryParameters['worker_id'] == 'eq.$worker'), true);
    expect(reads.last.url.queryParameters['select'], isNot(contains('attachment_paths')));
  });
}

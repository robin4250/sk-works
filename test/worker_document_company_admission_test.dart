import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/people/worker_document_repository.dart';

const actor = '80000000-0000-0000-0000-000000000001';
const company = '80000000-0000-0000-0000-000000000002';
const other = '80000000-0000-0000-0000-000000000003';
const worker = '80000000-0000-0000-0000-000000000004';
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
      'created_at': '2026-10-31T00:00:00Z',
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
    {'company_id': company, 'role': 'admin'},
  ];
  int initializers = 0;
  bool missingWorker = false;
  Completer<void>? membershipWait, workerWait;
  final membershipStarted = Completer<void>(),
      workerStarted = Completer<void>();
  Future<void> login(String sid) =>
      client.auth.setInitialSession(jsonEncode(session(sid)));
  static Future<Fixture> create() async {
    final f = Fixture();
    f.client = SupabaseClient(
      'https://company-admission.synthetic.invalid',
      'synthetic-public',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((r) async {
        f.requests.add(r);
        Object? value;
        switch (r.url.path.split('/').last) {
          case 'company_members':
            if (f.membershipWait != null) {
              if (!f.membershipStarted.isCompleted) {
                f.membershipStarted.complete();
              }
              await f.membershipWait!.future;
            }
            value = f.memberships;
          case 'ensure_current_user_worker':
            f.initializers++;
            value = worker;
          case 'workers':
            if (f.workerWait != null) {
              if (!f.workerStarted.isCompleted) {
                f.workerStarted.complete();
              }
              await f.workerWait!.future;
            }
            value = f.missingWorker ? null : {'name': 'Synthetic employee'};
          default:
            throw StateError('Unexpected fixture endpoint');
        }
        return http.Response(
          jsonEncode(value),
          200,
          headers: {'content-type': 'application/json'},
          request: r,
        );
      }),
    );
    await f.login('sid-a');
    f.repository = WorkerDocumentRepository.forTesting(f.client);
    return f;
  }

  Future<void> close() => client.dispose();
}

void main() {
  test('one verified company keeps existing initialization but binds its worker read and bearer', () async {
    final f = await Fixture.create();
    addTearDown(f.close);
    final bearer = 'Bearer ${f.client.auth.currentSession!.accessToken}';
    final value = await f.repository.currentWorker();
    expect(value.workerId, worker);
    expect(f.initializers, 1);
    final membership = f.requests.singleWhere(
      (r) => r.url.path.endsWith('company_members'),
    );
    expect(membership.url.queryParameters['limit'], '2');
    expect(membership.url.queryParameters['user_id'], 'eq.$actor');
    final selected = f.requests.singleWhere(
      (r) => r.url.path.endsWith('workers'),
    );
    expect(selected.url.queryParameters['company_id'], 'eq.$company');
    expect(selected.url.queryParameters['user_id'], 'eq.$actor');
    expect(selected.url.queryParameters['id'], 'eq.$worker');
    expect(selected.url.queryParameters['status'], 'eq.active');
    expect(f.requests.every((r) => r.headers['Authorization'] == bearer), true);
    expect(
      f.requests
          .where((r) => r.method != 'GET')
          .map((r) => r.url.path.split('/').last),
      ['ensure_current_user_worker'],
    );
  });
  test('empty, multiple or duplicate memberships stop before a mutating initializer', () async {
    for (final members in <List<Map<String, dynamic>>>[
      [],
      [
        {'company_id': company, 'role': 'admin'},
        {'company_id': other, 'role': 'admin'},
      ],
      [
        {'company_id': company, 'role': 'admin'},
        {'company_id': company, 'role': 'admin'},
      ],
    ]) {
      final f = await Fixture.create();
      addTearDown(f.close);
      f.memberships = members;
      await expectLater(f.repository.currentWorker(), throwsStateError);
      expect(f.initializers, 0);
      expect(f.requests.any((r) => r.url.path.endsWith('workers')), false);
    }
  });
  test('an ambiguous manager cannot acquire editing authority from the first membership', () async {
    final f = await Fixture.create();
    addTearDown(f.close);
    f.memberships.add({'company_id': other, 'role': 'viewer'});
    await expectLater(f.repository.canManageStatuses(), throwsStateError);
    expect(f.initializers, 0);
  });
  test(
    'new SID during the membership lookup prevents initialization',
    () async {
      final f = await Fixture.create();
      addTearDown(f.close);
      f.membershipWait = Completer<void>();
      final pending = f.repository.currentWorker();
      final rejected = expectLater(pending, throwsStateError);
      await f.membershipStarted.future.timeout(const Duration(seconds: 5));
      await f.login('sid-b');
      f.membershipWait!.complete();
      await rejected;
      expect(f.initializers, 0);
    },
  );
  test('late worker response from the previous SID is not accepted as current evidence', () async {
    final f = await Fixture.create();
    addTearDown(f.close);
    f.workerWait = Completer<void>();
    final pending = f.repository.currentWorker();
    final rejected = expectLater(pending, throwsStateError);
    await f.workerStarted.future.timeout(const Duration(seconds: 5));
    await f.login('sid-b');
    f.workerWait!.complete();
    await rejected;
    expect(f.initializers, 1);
  });
  test(
    'a worker absent from the bound company/person/active query fails closed',
    () async {
      final f = await Fixture.create();
      addTearDown(f.close);
      f.missingWorker = true;
      await expectLater(f.repository.currentWorker(), throwsStateError);
      expect(f.initializers, 1);
    },
  );
}


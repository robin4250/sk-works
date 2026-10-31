import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/people/worker_document_repository.dart';

const actor = '10000000-0000-0000-0000-000000000001';
const company = '20000000-0000-0000-0000-000000000001';
const worker = '30000000-0000-0000-0000-000000000001';
const requirement = '40000000-0000-0000-0000-000000000001';
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
  List<Map<String, dynamic>> metadata = [
    {
      'worker_id': worker,
      'company_id': company,
      'updated_at': '2026-10-31T00:00:00Z',
    },
  ];
  bool deny = false, retired = false;
  Completer<void>? wait;
  final metadataStarted = Completer<void>();
  Future<void> login(String sid) =>
      client.auth.setInitialSession(jsonEncode(session(sid)));
  static Future<Fixture> create() async {
    final f = Fixture();
    f.client = SupabaseClient(
      'https://metadata-fixture.invalid',
      'synthetic-public',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        f.requests.add(request);
        Object? value;
        var code = 200;
        switch (request.url.path.split('/').last) {
          case 'company_members':
            value = [
              {'company_id': company, 'role': 'admin'},
            ];
          case 'worker_document_exemption':
            value = {'capability_version': 1, 'can_manage': false, 'items': []};
          case 'document_requirements':
            value = [
              {
                'id': requirement,
                'company_id': company,
                'name': '銀行口座情報',
                'is_active': true,
                'archived_at': null,
                'is_required': true,
              },
            ];
          case 'workers':
            value = f.retired
                ? []
                : [
                    {
                      'id': worker,
                      'company_id': company,
                      'status': 'active',
                      'name': 'synthetic',
                    },
                  ];
          case 'worker_document_statuses':
            value = [];
          case 'worker_private_bank_accounts':
            if (f.wait != null) {
              if (!f.metadataStarted.isCompleted) {
                f.metadataStarted.complete();
              }
              await f.wait!.future;
            }
            if (f.deny) {
              code = 403;
              value = {'code': '42501', 'message': 'synthetic denied'};
            } else {
              value = f.metadata;
            }
          default:
            throw StateError('Unexpected endpoint ${request.url.path}');
        }
        return http.Response(
          jsonEncode(value),
          code,
          headers: {'content-type': 'application/json'},
          request: request,
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
  test(
    'managed status uses only existing RLS-scoped metadata and captured bearer',
    () async {
      final f = await Fixture.create();
      addTearDown(f.close);
      final token = f.client.auth.currentSession!.accessToken;
      final rows = await f.repository.loadAll();
      expect(rows['bank_account_metadata'], f.metadata);
      final read = f.requests.singleWhere(
        (r) => r.url.path.endsWith('worker_private_bank_accounts'),
      );
      expect(read.method, 'GET');
      expect(
        read.url.queryParameters['select'],
        'worker_id,company_id,updated_at',
      );
      expect(read.url.queryParameters['company_id'], 'eq.$company');
      expect(read.url.queryParameters['worker_id'], 'in.("$worker")');
      expect(read.headers['Authorization'], 'Bearer $token');
      expect(
        f.requests.every(
          (r) =>
              r.method == 'GET' ||
              r.url.path.endsWith('/worker_document_exemption'),
        ),
        true,
      );
    },
  );
  test(
    'denied or invisible metadata remains unknown without guessing absence',
    () async {
      final f = await Fixture.create();
      addTearDown(f.close);
      f.deny = true;
      expect((await f.repository.loadAll())['bank_account_metadata'], isEmpty);
      f.deny = false;
      f.metadata = [];
      expect((await f.repository.loadAll())['bank_account_metadata'], isEmpty);
    },
  );
  test('foreign, duplicate, unexpected sensitive fields or invalid dates fail closed', () async {
    for (final kind in ['foreign', 'duplicate', 'sensitive', 'date']) {
      final f = await Fixture.create();
      addTearDown(f.close);
      if (kind == 'foreign') {
        f.metadata.single['company_id'] = 'foreign';
      }
      if (kind == 'duplicate') {
        f.metadata.add(Map.of(f.metadata.single));
      }
      if (kind == 'sensitive') {
        f.metadata.single['account_number'] = 'synthetic-forbidden';
      }
      if (kind == 'date') {
        f.metadata.single['updated_at'] = 'invalid';
      }
      await expectLater(f.repository.loadAll(), throwsStateError);
    }
  });
  test('new SID while metadata is pending discards the old result', () async {
    final f = await Fixture.create();
    addTearDown(f.close);
    f.wait = Completer<void>();
    final pending = f.repository.loadAll();
    final rejected = expectLater(pending, throwsStateError);
    await f.metadataStarted.future.timeout(const Duration(seconds: 5));
    await f.login('sid-b');
    f.wait!.complete();
    await rejected;
  });
  test('worker retirement during metadata read discards the proof', () async {
    final f = await Fixture.create();
    addTearDown(f.close);
    f.wait = Completer<void>();
    final pending = f.repository.loadAll();
    final rejected = expectLater(pending, throwsStateError);
    await f.metadataStarted.future.timeout(const Duration(seconds: 5));
    f.retired = true;
    f.wait!.complete();
    await rejected;
  });
}

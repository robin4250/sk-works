import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/people/worker_document_repository.dart';

void main() {
  test('archive compares every field and preserves scoped hidden state; restore uses same ID', () async {
    const actor = '10000000-0000-0000-0000-000000000002';
    const company = '10000000-0000-0000-0000-000000000001';
    const requirement = '10000000-0000-0000-0000-000000000004';
    final requests = <({String method, Uri uri, dynamic body})>[];
    var role = 'manager';
    var noMatchingRow = false;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      final data = await utf8.decoder.bind(r).join();
      requests.add((
        method: r.method,
        uri: r.uri,
        body: data.isEmpty ? null : jsonDecode(data),
      ));
      Object response;
      if (r.uri.path == '/auth/v1/token') {
        String encode(Object v) =>
            base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
        response = {
          'access_token':
              '${encode({'alg': 'HS256'})}.${encode({'sub': actor, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.fixture',
          'refresh_token': 'fixture',
          'token_type': 'bearer',
          'expires_in': 3600,
          'user': {
            'id': actor,
            'aud': 'authenticated',
            'role': 'authenticated',
            'email': 'fixture@example.test',
            'app_metadata': {},
            'user_metadata': {},
            'created_at': '2026-01-01T00:00:00Z',
          },
        };
      } else if (r.uri.path == '/rest/v1/company_members') {
        response = [
          {'company_id': company, 'role': role},
        ];
      } else if (r.uri.path == '/rest/v1/document_requirements' &&
          r.method == 'PATCH') {
        response = noMatchingRow
            ? []
            : [
                {'id': requirement, 'archived_at': (jsonDecode(data) as Map)['archived_at'], 'is_active': false},
              ];
      } else {
        r.response.statusCode = 500;
        response = {'message': 'Unexpected request'};
      }
      r.response.headers.contentType = ContentType.json;
      r.response.write(jsonEncode(response));
      await r.response.close();
    });
    final client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'fixture',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    try {
      await client.auth.signInWithPassword(
        email: 'fixture@example.test',
        password: 'fixture',
      );
      requests.clear();
      final repo = WorkerDocumentRepository.forTesting(client);
      final row = <String, dynamic>{
        'id': requirement, 'company_id': company, 'name': '重複書類',
        'scope': 'both', 'upstream_name': '取引会社', 'company_template_id': null,
        'is_required': true, 'expiry_required': false,
        'renewal_reminder_days': 30, 'is_active': false, 'sort_order': 10,
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z', 'archived_at': null,
      };
      await repo.archiveRequirement(row);
      final write = requests.singleWhere((r) => r.method == 'PATCH');
      expect(write.body['is_active'], false);
      expect(write.body['archived_at'], isA<String>());
      expect(write.body['updated_at'], write.body['archived_at']);
      expect(write.uri.queryParameters['company_id'], 'eq.$company');
      expect(write.uri.queryParameters['id'], 'eq.$requirement');
      for (final key in ['name', 'scope', 'upstream_name', 'is_required',
          'expiry_required', 'renewal_reminder_days', 'is_active', 'sort_order',
          'created_at', 'updated_at']) {
        expect(write.uri.queryParameters[key], 'eq.${row[key]}', reason: key);
      }
      expect(write.uri.queryParameters['archived_at'], 'is.null');
      expect(write.uri.queryParameters['company_template_id'], 'is.null');
      requests.clear();
      final archived = {...row, 'archived_at': write.body['archived_at']};
      await repo.restoreRequirement(archived);
      final restore = requests.singleWhere((r) => r.method == 'PATCH');
      expect(restore.body['archived_at'], isNull);
      expect(restore.body['is_active'], false);
      expect(restore.uri.queryParameters['id'], 'eq.$requirement');
      expect(restore.uri.queryParameters['archived_at'], 'eq.${archived['archived_at']}');
      requests.clear();
      role = 'employee';
      await expectLater(repo.archiveRequirement(row), throwsStateError);
      expect(requests.where((r) => r.method != 'GET'), isEmpty);
      role = 'manager';
      requests.clear();
      await expectLater(repo.archiveRequirement({...row, 'company_id': 'another'}), throwsStateError);
      expect(requests.where((r) => r.method != 'GET'), isEmpty);
      noMatchingRow = true;
      await expectLater(repo.archiveRequirement(row), throwsStateError);
      requests.clear();
      final unsupported = Map<String, dynamic>.from(row)..remove('archived_at');
      await expectLater(repo.archiveRequirement(unsupported), throwsStateError);
      expect(requests, isEmpty);
    } finally {
      await client.dispose();
      await server.close(force: true);
    }
  });
}


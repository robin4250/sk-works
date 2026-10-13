import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/people/worker_document_repository.dart';

void main() {
  test('requirement removal updates only the scoped active row; employee role cannot write', () async {
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
                {'id': requirement},
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
      await repo.deactivateRequirement(requirement);
      final writes = requests.where((r) => r.method != 'GET').toList();
      expect(writes.length, 1);
      expect(writes.single.method, 'PATCH');
      expect(writes.single.body, {'is_active': false});
      expect(writes.single.uri.queryParameters['company_id'], 'eq.$company');
      expect(writes.single.uri.queryParameters['id'], 'eq.$requirement');
      expect(writes.single.uri.queryParameters['is_active'], 'eq.true');
      requests.clear();
      role = 'employee';
      await expectLater(
        repo.deactivateRequirement(requirement),
        throwsStateError,
      );
      expect(requests.where((r) => r.method != 'GET'), isEmpty);
      role = 'manager';
      noMatchingRow = true;
      await expectLater(
        repo.deactivateRequirement(requirement),
        throwsStateError,
      );
    } finally {
      await client.dispose();
      await server.close(force: true);
    }
  });
}

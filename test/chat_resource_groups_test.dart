import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/albums/albums_cloud_repository.dart';
import 'package:sk_works/features/notes/notes_cloud_repository.dart';

const actor = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final album in [false, true]) {
    late SupabaseClient client;
    late List<http.Request> calls;
    Object classification = ['analysis'];
    int classificationStatus = 200;
    setUp(() async {
      calls = [];
      classification = ['analysis'];
      classificationStatus = 200;
      client = SupabaseClient('https://resource-groups.invalid', 'synthetic-public',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          calls.add(request);
          Object data;
          var status = 200;
          if (request.url.path.endsWith('/company_members')) {
            expect(request.url.queryParameters['user_id'], 'eq.$actor');
            data = [{'company_id': 'company'}];
          } else if (request.url.path.endsWith('/rpc/line_history_analysis_ids')) {
            data = classification;
            status = classificationStatus;
          } else if (request.url.path.endsWith('/communication_groups')) {
            expect(request.url.queryParameters['company_id'], 'eq.company');
            expect(request.url.queryParameters['order'], 'name.asc');
            data = [
              {'id': 'analysis', 'name': '過去履歴分析：original.zip', 'group_type': 'company'},
              {'id': 'site', 'name': '江戸川', 'group_type': 'site'},
              {'id': 'real-zip', 'name': '過去履歴分析：ordinary.zip', 'group_type': 'company'},
              {'id': 'custom', 'name': 'すみだ建設出勤', 'group_type': 'company'},
            ];
          } else {
            throw StateError('Unexpected fixture route: ${request.url.path}');
          }
          return http.Response(jsonEncode(data), status,
            headers: {'content-type': 'application/json'}, request: request);
        }));
      await client.auth.setInitialSession(jsonEncode({
        'access_token': '${base64Url.encode(utf8.encode(jsonEncode({'alg': 'HS256'}))).replaceAll('=', '')}.${base64Url.encode(utf8.encode(jsonEncode({'sub': actor, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600}))).replaceAll('=', '')}.synthetic',
        'refresh_token': 'synthetic-refresh',
        'token_type': 'bearer', 'expires_in': 3600,
        'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
        'user': {'id': actor, 'aud': 'authenticated', 'role': 'authenticated',
          'email': 'fixture@example.invalid', 'app_metadata': {}, 'user_metadata': {},
          'created_at': '2026-10-01T00:00:00Z'},
      }));
    });
    tearDown(() async => client.dispose());

    Future<List<Map<String, dynamic>>> load() => album
      ? AlbumsCloudRepository.forTesting(client).loadGroups()
      : NotesCloudRepository.forTesting(client).loadGroups();

    test('HOME resource groups exclude exact analysis IDs without deleting: albums=$album', () async {
      final groups = await load();
      expect(groups.map((row) => row['id']), ['site', 'real-zip', 'custom']);
      expect(groups[1]['name'], '過去履歴分析：ordinary.zip');
      expect(calls.map((request) => request.method), ['GET', 'POST', 'GET']);
      expect(calls.where((request) => request.method == 'DELETE'), isEmpty);
    });
    test('classification permission errors fail closed: albums=$album', () async {
      classificationStatus = 403;
      classification = {'code': '42501', 'message': 'not authorized'};
      await expectLater(load(), throwsA(isA<PostgrestException>()));
      expect(calls.any((request) => request.url.path.endsWith('/communication_groups')), isFalse);
    });
    test('malformed classification does not show analysis destination: albums=$album', () async {
      classification = {'ids': ['analysis']};
      await expectLater(load(), throwsStateError);
      expect(calls.any((request) => request.url.path.endsWith('/communication_groups')), isFalse);
    });
    test('pre-migration server preserves ordinary chat rollout compatibility: albums=$album', () async {
      classificationStatus = 404;
      classification = {'code': 'PGRST202', 'message': 'function missing'};
      expect(await load(), hasLength(4));
    });
  }
}

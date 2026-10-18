import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sk_works/features/sites/site_map_notification_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const id = '11111111-1111-4111-8111-111111111111';
void main() {
  test(
    'adapter uses one exact verification GET with saved coordinates, no RPC/latest query',
    () async {
      final calls = <http.Request>[];
      final client = SupabaseClient(
        'https://map-notice-fixture.invalid',
        'fixture-public',
        httpClient: MockClient((request) async {
          calls.add(request);
          return http.Response(
            jsonEncode({'id': id}),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(client.dispose);
      final source = SupabaseSiteMapNoticeSource(client);
      expect((await source.target(id))?['id'], id);
      expect(calls, hasLength(1));
      final request = calls.single;
      expect(request.method, 'GET');
      expect(request.url.path, '/rest/v1/attendance_verifications');
      expect(request.url.queryParameters, {
        'select': SupabaseSiteMapNoticeSource.columns,
        'id': 'eq.$id',
      });
      expect(request.body, isEmpty);
      expect(
        SupabaseSiteMapNoticeSource.columns,
        contains('latitude,longitude'),
      );
    },
  );

  test(
    'adapter keeps missing response null and propagates denied response without retry',
    () async {
      for (final status in [200, 403]) {
        var calls = 0;
        final client = SupabaseClient(
          'https://map-notice-fixture.invalid',
          'fixture-public',
          httpClient: MockClient((request) async {
            calls++;
            return http.Response(
              status == 200 ? '[]' : '{"message":"denied","code":"42501"}',
              status,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }),
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        );
        final source = SupabaseSiteMapNoticeSource(client);
        if (status == 200) {
          expect(await source.target(id), isNull);
        } else {
          await expectLater(
            source.target(id),
            throwsA(isA<PostgrestException>()),
          );
        }
        expect(calls, 1);
        await client.dispose();
      }
    },
  );
}

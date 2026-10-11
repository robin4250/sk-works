import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/operations/vehicle_route_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  for (final outcome in ['success', 'missing RPC', 'unconfirmed']) {
    test('route clear $outcome never falls back to individual table writes', () async {
      final paths = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        paths.add(request.uri.path);
        Object? response;
        if (request.uri.path == '/auth/v1/token') {
          String encode(Object value) => base64Url
              .encode(utf8.encode(jsonEncode(value)))
              .replaceAll('=', '');
          const actor = '11111111-1111-4111-8111-111111111111';
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
        } else if (request.uri.path.endsWith(
          '/clear_my_route_attendance_selection',
        )) {
          expect(jsonDecode(await utf8.decoder.bind(request).join()), {});
          final today = DateTime.now().toUtc().add(const Duration(hours: 9));
          final date =
              '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
          response = {
            'cleared': outcome == 'success',
            'work_date': date,
            'route_assignment_id': null,
          };
          if (outcome == 'missing RPC') {
            request.response.statusCode = 404;
            response = {
              'message': 'function is unavailable',
              'code': 'PGRST202',
            };
          }
        } else {
          request.response.statusCode = 500;
          response = {'message': 'Unexpected mutation or lookup'};
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(response));
        await request.response.close();
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
        paths.clear();
        final clear = VehicleRouteRepository.forTesting(client)
            .saveTodayRouteSelection(null);
        if (outcome == 'success') {
          await clear;
        } else {
          await expectLater(
            clear,
            outcome == 'missing RPC'
                ? throwsA(isA<PostgrestException>())
                : throwsStateError,
          );
        }
        expect(paths, ['/rest/v1/rpc/clear_my_route_attendance_selection']);
      } finally {
        await client.dispose();
        await server.close(force: true);
      }
    });
  }
}

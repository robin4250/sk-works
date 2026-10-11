import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/operations/vehicle_route_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  for (final mode in ['filled', 'clear', 'legacy', 'off']) {
    test('route responsible contact $mode respects saved and omitted values', () async {
      final writes = <Map<String, dynamic>>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
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
        } else if (request.uri.path == '/auth/v1/logout') {
          response = {};
        } else if (request.uri.path.endsWith('/current_master_feature_flags')) {
          response = {
            'vehicle_management': true,
            'route_assignment': mode != 'off',
          };
        } else if (request.uri.path == '/rest/v1/company_members') {
          response = [
            {'company_id': '22222222-2222-4222-8222-222222222222'},
          ];
        } else if (request.uri.path == '/rest/v1/route_assignments') {
          if (request.method == 'GET') {
            expect(
              request.uri.queryParameters['select'],
              contains('responsible_name,responsible_phone'),
            );
            response = [
              {
                'id': 'route',
                'route_name': 'route',
                'responsible_name': '責任者',
                'responsible_phone': '03-1234-5678',
                'route_stops': [],
              },
            ];
          } else {
            writes.add(
              Map<String, dynamic>.from(
                jsonDecode(await utf8.decoder.bind(request).join()),
              ),
            );
            response = null;
          }
        } else if (request.uri.path == '/rest/v1/route_stops' &&
            request.method == 'DELETE') {
          response = null;
        } else {
          request.response.statusCode = 500;
          response = {'message': 'Unexpected request'};
        }
        request.response.headers.contentType = ContentType.json;
        if (response != null) request.response.write(jsonEncode(response));
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
        final repo = VehicleRouteRepository.forTesting(client);
        final rows = await repo.routes();
        expect(rows.single['responsible_name'], '責任者');
        expect(rows.single['responsible_phone'], '03-1234-5678');
        final future = repo.saveRoute(
          id: 'route',
          name: 'route',
          notes: '',
          stops: [],
          responsibleName: mode == 'legacy'
              ? null
              : mode == 'clear'
              ? '  '
              : ' 責任者 ',
          responsiblePhone: mode == 'legacy'
              ? null
              : mode == 'clear'
              ? ''
              : ' 03-1234-5678 ',
        );
        if (mode == 'off') {
          await expectLater(future, throwsStateError);
          expect(writes, isEmpty);
        } else {
          await future;
          expect(writes, hasLength(1));
          final data = writes.single;
          if (mode == 'legacy') {
            expect(data.containsKey('responsible_name'), false);
            expect(data.containsKey('responsible_phone'), false);
          } else {
            expect(data['responsible_name'], mode == 'clear' ? null : '責任者');
            expect(
              data['responsible_phone'],
              mode == 'clear' ? null : '03-1234-5678',
            );
          }
        }
      } finally {
        await client.dispose();
        await server.close(force: true);
      }
    });
  }
}

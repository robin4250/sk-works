import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/attendance/attendance_verification_repository.dart';
import 'package:sk_works/features/attendance/attendance_shift_context.dart';

void main() {
  for (final scenario in [
    'saved',
    'race',
    'mismatch',
    'read-failure',
    'actor-change',
    'actor-company-read',
    'actor-insert-response',
  ]) {
    test('manual route checkout recovery: $scenario', () async {
      const actor = '10000000-0000-0000-0000-000000000002';
      const company = '10000000-0000-0000-0000-000000000001';
      const worker = '10000000-0000-0000-0000-000000000003';
      final saved = <String, dynamic>{
        'id': 'saved-end',
        'company_id': company,
        'worker_id': worker,
        'source_clock_in_id': 'start',
        'event_type': 'clock_out',
        'site_id': null,
        'route_assignment_id': 'route',
        'vehicle_id': null,
        'work_date': '2026-10-11',
        'confirmed_at': '2026-10-11T02:00:00Z',
        'daily_report_id': null,
      };
      final shift = AttendanceShiftContext(
        id: 'start',
        workerId: worker,
        workDate: DateTime(2026, 10, 11),
        clockIn: DateTime(2026, 10, 11, 9),
        verificationMode: 'manual',
        routeId: 'route',
      );
      var inserts = 0;
      var reads = 0;
      late SupabaseClient client;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        await utf8.decoder.bind(request).join();
        Object? response;
        final path = request.uri.path;
        if (path == '/auth/v1/token') {
          String enc(Object v) =>
              base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
          response = {
            'access_token':
                '${enc({'alg': 'HS256'})}.${enc({'sub': actor, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.fixture',
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
        } else if (path.endsWith('/company_members')) {
          if (scenario == 'actor-company-read') {
            await client.auth.signOut(scope: SignOutScope.local);
          }
          response = [
            {'company_id': company},
          ];
        } else if (path.endsWith('/work_vehicle_route_selections')) {
          response = {'route_assignment_id': 'route', 'vehicle_id': null};
        } else if (path.endsWith('/attendance_verifications')) {
          if (request.method == 'GET') {
            reads++;
            expect(
              request.uri.queryParameters['source_clock_in_id'],
              'eq.start',
            );
            expect(request.uri.queryParameters['company_id'], 'eq.$company');
            expect(request.uri.queryParameters['worker_id'], 'eq.$worker');
            if (scenario == 'actor-change') {
              await client.auth.signOut(scope: SignOutScope.local);
            }
            if (scenario == 'read-failure') {
              request.response.statusCode = 503;
              response = {'code': 'PGRST000', 'message': 'Unavailable'};
            } else if ((scenario == 'race' ||
                    scenario == 'actor-insert-response') &&
                reads == 1) {
              response = null;
            } else {
              response = {
                ...saved,
                if (scenario == 'mismatch')
                  'route_assignment_id': 'foreign-route',
              };
            }
          } else {
            inserts++;
            if (scenario == 'actor-insert-response') {
              await client.auth.signOut(scope: SignOutScope.local);
              response = saved;
            } else {
              request.response.statusCode = 409;
              response = {
                'code': '23505',
                'message':
                    'duplicate key attendance_verifications_one_out_per_start',
              };
            }
          }
        } else {
          request.response.statusCode = 500;
          response = {'message': 'Unexpected $path'};
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(response));
        await request.response.close();
      });
      client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'fixture',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      try {
        await client.auth.signInWithPassword(
          email: 'fixture@example.test',
          password: 'fixture',
        );
        final repository = AttendanceVerificationRepository.forTesting(client);
        final operation = repository.createVerification(
          workerId: worker,
          eventType: 'clock_out',
          verificationMode: 'manual',
          proximityStatus: 'not_required',
          shift: shift,
        );
        if (scenario == 'saved' || scenario == 'race') {
          expect(await operation, saved);
          // A second tap or reopening returns the original end and actual time.
          expect(
            await repository.createVerification(
              workerId: worker,
              eventType: 'clock_out',
              verificationMode: 'manual',
              proximityStatus: 'not_required',
              shift: shift,
            ),
            saved,
          );
          expect(inserts, scenario == 'race' ? 1 : 0);
        } else {
          await expectLater(operation, throwsA(anything));
          expect(inserts, scenario == 'actor-insert-response' ? 1 : 0);
          if (scenario == 'actor-company-read') expect(reads, 0);
          if (scenario == 'actor-insert-response') expect(reads, 1);
        }
      } finally {
        await client.dispose();
        await server.close(force: true);
      }
    });
  }
}

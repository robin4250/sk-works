import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/attendance/route_journey_capture_repository.dart';
import 'package:sk_works/features/attendance/route_journey_capture_draft.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final mismatch in [
    null,
    'company_id',
    'report_date',
    'created_by',
    'source_clock_in_id',
    'route_assignment_id',
    'route_stop_id',
    'start_capture_id',
    'end_capture_id',
  ]) {
    test(
      'reporter signed resume validates ${mismatch ?? 'matching visit'} before cleanup',
      () async {
        SharedPreferences.setMockInitialValues({});
        const actor = '11111111-1111-4111-8111-111111111111';
        final move = RouteJourneyCaptureDraft(
          userId: actor,
          companyId: 'company',
          sourceId: 'source',
          stopId: 'stop',
          originKind: 'company',
          visitKind: 'end',
          startCaptureId: 'arrival',
          payload: {'capture_contract_version': 1},
        );
        final pending = RouteVisitReportPending.fromSaved(move, {
          'id': move.id,
          'created_by': actor,
          'company_id': 'company',
          'source_clock_in_id': 'source',
          'route_stop_id': 'stop',
          'origin_kind': 'company',
          'visit_kind': 'end',
          'start_capture_id': 'arrival',
          'work_date': '2026-10-11',
          'recorded_at': '2026-10-11T01:00:00Z',
          'payload': move.payload,
        });
        var terminal = false;
        final paths = <String>[];
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) async {
          paths.add(request.uri.path);
          Object response;
          if (request.uri.path == '/auth/v1/token') {
            String encode(Object value) => base64Url
                .encode(utf8.encode(jsonEncode(value)))
                .replaceAll('=', '');
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
          } else if (request.uri.path.endsWith('/company_members')) {
            response = [
              {'company_id': 'company'},
            ];
          } else if (request.uri.path.endsWith(
            '/route_journey_visit_workspace',
          )) {
            response = {
              'version': 1,
              'source_clock_in_id': 'source',
              'company_id': 'company',
              'work_date': '2026-10-11',
              'route_assignment_id': 'route',
            };
          } else if (request.uri.path.endsWith('/choose_route_visit_report') ||
              request.uri.path.endsWith('/read_route_visit_report')) {
            final body =
                jsonDecode(await utf8.decoder.bind(request).join()) as Map;
            expect(body['p_end_capture_id'], move.id);
            response = {
              'id': 'report',
              'status': terminal ? 'completed' : 'reporter_signed',
              'company_id': 'company',
              'created_by': actor,
              'report_date': '2026-10-11',
              'source_clock_in_id': 'source',
              'route_assignment_id': 'route',
              'route_stop_id': 'stop',
              'start_capture_id': 'arrival',
              'end_capture_id': move.id,
              if (mismatch != null) mismatch: 'wrong',
            };
          } else {
            request.response.statusCode = 500;
            response = {'message': 'unexpected request'};
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
          final repository = RouteJourneyCaptureRepository.forTesting(client);
          if (mismatch == null) {
            final selected = await repository.chooseReport(pending, 'create');
            expect(selected.choice, 'create');
            expect(
              (await repository.allPendingReports()).single.endCaptureId,
              move.id,
            );
            await expectLater(
              repository.finishReport(selected),
              throwsStateError,
            );
            terminal = true;
            await repository.finishReport(selected);
            expect(await repository.allPendingReports(), isEmpty);
          } else {
            await expectLater(
              repository.chooseReport(pending, 'create'),
              throwsStateError,
            );
            terminal = true;
            await expectLater(
              repository.finishReport(pending),
              throwsStateError,
            );
            expect(
              (await repository.allPendingReports()).single.endCaptureId,
              move.id,
            );
          }
          expect(
            paths.where((path) => path.contains('save_route_journey')),
            isEmpty,
          );
        } finally {
          await client.dispose();
          await server.close(force: true);
        }
      },
    );
  }
}

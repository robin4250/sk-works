import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/attendance_verification_page.dart';
import 'package:sk_works/features/attendance/attendance_verification_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('manual route clock-in preserves route despite stale GPS site', () async {
    const company = '10000000-0000-0000-0000-000000000001';
    const actor = '10000000-0000-0000-0000-000000000002';
    const worker = '10000000-0000-0000-0000-000000000003';
    const route = '10000000-0000-0000-0000-000000000004';
    const site = '10000000-0000-0000-0000-000000000005';
    String? persistedRoute = route;
    Map<String, dynamic>? saved;
    final requests = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      final path = request.uri.path;
      requests.add('${request.method} $path');
      Object? response;
      if (path == '/auth/v1/token') {
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
      } else if (path.endsWith('/company_members')) {
        response = [
          {'company_id': company},
        ];
      } else if (path.endsWith('/ensure_current_user_worker')) {
        response = worker;
      } else if (path.endsWith('/work_vehicle_route_selections')) {
        if (request.method == 'PATCH') persistedRoute = null;
        response = request.method == 'GET'
            ? {'route_assignment_id': persistedRoute, 'vehicle_id': null}
            : null;
      } else if (path.endsWith('/work_attendance_selections')) {
        response = null;
      } else if (path.endsWith('/save_my_route_attendance_selection')) {
        expect(jsonDecode(body)['p_route_assignment_id'], route);
        response = {'mode': 'manual', 'route_assignment_id': route};
      } else if (path.endsWith('/save_my_attendance_selection')) {
        response = {'mode': 'manual', 'site_id': site};
      } else if (path.endsWith('/attendance_verifications')) {
        saved = Map<String, dynamic>.from(jsonDecode(body) as Map);
        response = {
          'id': 'record',
          'confirmed_at': '2026-10-11T01:25:00Z',
          'work_date': '2026-10-11',
          'source_clock_in_id': null,
        };
      } else {
        request.response.statusCode = 500;
        response = {'message': 'Unexpected fixture endpoint $path'};
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
      final repository = AttendanceVerificationRepository.forTesting(client);
      final destination = resolveAttendanceClockInDestination(
        selection: {
          'mode': 'manual',
          'site_id': null,
          'route_assignment_id': route,
        },
        gpsSchedule: {'site_id': site, 'enabled': false},
        selectedRouteId: route,
      );
      expect(destination, (siteId: null, routeId: route));
      await repository.saveAttendanceSelection(
        mode: 'manual',
        siteId: destination.siteId,
      );
      await repository.createVerification(
        workerId: worker,
        siteId: destination.siteId,
        eventType: 'clock_in',
        verificationMode: 'manual',
        proximityStatus: 'not_required',
      );
      expect(saved?['site_id'], isNull);
      expect(saved?['route_assignment_id'], route);
      expect(requests.where((r) => r.startsWith('PATCH ')), isEmpty);
      expect(
        requests.any((r) => r.endsWith('/save_my_attendance_selection')),
        isFalse,
      );
      // An explicit site choice must still replace the prior route.
      final explicitSite = resolveAttendanceClockInDestination(
        selection: {
          'mode': 'manual',
          'site_id': site,
          'route_assignment_id': null,
        },
        gpsSchedule: {'site_id': 'stale'},
        selectedRouteId: route,
      );
      expect(explicitSite, (siteId: site, routeId: null));
      await repository.saveAttendanceSelection(
        mode: 'manual',
        siteId: explicitSite.siteId,
      );
      await repository.createVerification(
        workerId: worker,
        siteId: explicitSite.siteId,
        eventType: 'clock_in',
        verificationMode: 'manual',
        proximityStatus: 'not_required',
      );
      expect(saved?['site_id'], site);
      expect(saved?['route_assignment_id'], isNull);
    } finally {
      await client.dispose();
      await server.close(force: true);
    }
  });
  test('GPS fallback applies only without an explicit daily destination', () {
    expect(
      resolveAttendanceClockInDestination(
        selection: {},
        gpsSchedule: {'site_id': 'legacy-site'},
      ),
      (siteId: 'legacy-site', routeId: null),
    );
    expect(
      resolveAttendanceClockInDestination(
        selection: {
          'mode': 'manual',
          'site_id': null,
          'route_assignment_id': null,
        },
        gpsSchedule: {'site_id': 'legacy-site'},
        selectedRouteId: 'stale-route',
      ),
      (siteId: null, routeId: null),
    );
    expect(
      resolveAttendanceClockInDestination(
        selection: {},
        gpsSchedule: {'site_id': 'legacy-site'},
        selectedRouteId: 'route',
      ),
      (siteId: null, routeId: 'route'),
    );
  });
}

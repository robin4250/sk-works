import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/attendance_verification_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  for (final scenario in [
    'normal',
    'closed_start_after_end',
    'tied',
    'future_start',
    'other_open',
  ]) {
    test('saved checkout home state: $scenario', () async {
      final now = DateTime.now();
      final day =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      Map<String, dynamic> event(
        String id,
        String type,
        DateTime time, {
        String? source,
      }) => {
        'id': id,
        'worker_id': 'worker',
        'event_type': type,
        'confirmed_at': time.toUtc().toIso8601String(),
        'work_date': day,
        'source_clock_in_id': source,
        'verification_mode': 'manual',
        'route_assignment_id': 'route',
        'route_assignments': {'route_name': '江戸川→東京海上→愛宕'},
      };
      final end = now.subtract(const Duration(minutes: 2));
      final start = switch (scenario) {
        'closed_start_after_end' => now.subtract(const Duration(minutes: 1)),
        'tied' => end,
        _ => now.subtract(const Duration(minutes: 3)),
      };
      final rows =
          [
            event('in', 'clock_in', start),
            event('out', 'clock_out', end, source: 'in'),
            if (scenario == 'future_start')
              event('future', 'clock_in', now.add(const Duration(hours: 1))),
            if (scenario == 'other_open')
              event(
                'other',
                'clock_in',
                now.subtract(const Duration(minutes: 1)),
              ),
          ]..sort(
            (a, b) => a['confirmed_at'].toString().compareTo(
              b['confirmed_at'].toString(),
            ),
          );
      // At equal timestamps the database can return the closed start last.
      if (scenario == 'tied') {
        rows.setAll(0, [rows[1], rows[0]]);
      }
      final requests = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        requests.add(request.method);
        Object? response;
        switch (request.uri.path) {
          case '/rest/v1/rpc/my_attendance_selection_workspace':
            response = {
              'selection': {'mode': 'manual'},
            };
          case '/rest/v1/rpc/ensure_current_user_worker':
            response = 'worker';
          case '/rest/v1/work_vehicle_route_selections':
            response = {
              'route_assignment_id': 'route',
              'route_assignments': {'route_name': '江戸川→東京海上→愛宕'},
            };
          case '/rest/v1/attendance_verifications':
            expect(request.uri.queryParameters['worker_id'], 'eq.worker');
            response = rows;
          default:
            request.response.statusCode = 500;
            response = {'message': 'Unexpected request'};
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
        final status = await AttendanceVerificationRepository.forTesting(client)
            .loadHomeAttendanceStatus();
        if (scenario == 'other_open') {
          expect(status.phase, HomeAttendancePhase.working);
          expect(status.openShifts.single.id, 'other');
          expect(status.clockOut, isNull);
        } else {
          expect(status.phase, HomeAttendancePhase.finished);
          expect(status.phaseLabel, '本日は退勤済');
          expect(status.openShifts, isEmpty);
          expect(status.clockOut, end);
        }
        expect(status.selectedRouteId, 'route');
        expect(requests, ['POST', 'POST', 'GET', 'GET']);
      } finally {
        await client.dispose();
        await server.close(force: true);
      }
    });
  }
}

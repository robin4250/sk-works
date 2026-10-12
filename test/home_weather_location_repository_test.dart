import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/attendance/attendance_shift_context.dart';
import 'package:sk_works/features/attendance/attendance_verification_repository.dart';
import 'package:sk_works/features/home/home_weather_location_repository.dart';
import 'package:sk_works/features/home/weather_forecast_policy.dart';

void main() {
  late HttpServer server;
  late SupabaseClient client;
  late List<Uri> requests;
  var role = 'worker';
  var companyVisible = true;
  var siteAddress = '現場';
  setUp(() async {
    role = 'worker';
    companyVisible = true;
    siteAddress = '現場';
    requests = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests.add(request.uri);
      request.response.headers.contentType = ContentType.json;
      final resource = request.uri.path.split('/').last;
      final Object body = switch (resource) {
        'company_members' => [
          {'company_id': 'company', 'role': role},
        ],
        'companies' =>
          companyVisible
              ? [
                  {'address': ''},
                ]
              : [],
        'current_worker_personnel_profile' => {'address': '自宅'},
        'sites' => [
          {'address': siteAddress},
        ],
        _ => [],
      };
      request.response.write(jsonEncode(body));
      await request.response.close();
    });
    client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'fixture',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final user = User(
      id: 'actor',
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-01-01T00:00:00Z',
    );
    await client.auth.setInitialSession(
      jsonEncode({
        'access_token':
            '${base64Url.encode(utf8.encode('{}'))}.${base64Url.encode(utf8.encode(jsonEncode({'exp': 4102444800, 'sub': 'actor'})))}.test',
        'refresh_token': 'fixture',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': user.toJson(),
      }),
    );
  });
  tearDown(() async {
    await client.dispose();
    await server.close(force: true);
  });

  for (final multiple in [false, true]) {
    test(
      'registered home with unavailable site is not a missing company address (multiple=$multiple)',
      () async {
        siteAddress = '';
        final shift = AttendanceShiftContext(
          id: 'shift',
          workerId: 'worker',
          workDate: DateTime(2026, 10, 12),
          clockIn: DateTime(2026, 10, 12, 8),
          verificationMode: 'manual',
          siteId: 'site',
        );
        final result = await HomeWeatherLocationRepository.forTesting(client)
            .load(
              HomeAttendanceStatus(
                phase: HomeAttendancePhase.working,
                openShifts: [shift, if (multiple) shift],
              ),
            );
        expect(result.selection.kind, WeatherAddressKind.unavailable);
        expect(result.selection.address, isNull);
        expect(result.companyAddressMissing, isFalse);
        if (multiple) {
          expect(requests.where((uri) => uri.path.endsWith('sites')), isEmpty);
        }
      },
    );
  }

  test(
    'route clock-in site does not masquerade as the current visit',
    () async {
      final shift = AttendanceShiftContext(
        id: 'route-shift',
        workerId: 'worker',
        workDate: DateTime(2026, 10, 12),
        clockIn: DateTime(2026, 10, 12, 8),
        verificationMode: 'manual',
        siteId: 'old-site',
        routeId: 'route',
      );
      final result = await HomeWeatherLocationRepository.forTesting(client)
          .load(
            HomeAttendanceStatus(
              phase: HomeAttendancePhase.working,
              openShifts: [shift],
            ),
          );
      expect(result.selection.kind, WeatherAddressKind.unavailable);
      expect(result.companyAddressMissing, isFalse);
      expect(requests.where((uri) => uri.path.endsWith('sites')), isEmpty);
    },
  );

  test(
    'employee uses only current company and active registered site',
    () async {
      final result = await HomeWeatherLocationRepository.forTesting(client)
          .load(
            HomeAttendanceStatus(
              phase: HomeAttendancePhase.working,
              openShifts: [
                AttendanceShiftContext(
                  id: 'shift',
                  workerId: 'worker',
                  workDate: DateTime(2026, 10, 12),
                  clockIn: DateTime(2026, 10, 12, 8),
                  verificationMode: 'manual',
                  siteId: 'site',
                ),
              ],
            ),
          );
      expect(result.selection.kind, WeatherAddressKind.site);
      expect(result.selection.address, '現場');
      final member = requests.singleWhere(
        (uri) => uri.path.endsWith('company_members'),
      );
      expect(member.queryParameters['user_id'], 'eq.actor');
      final site = requests.singleWhere((uri) => uri.path.endsWith('sites'));
      expect(site.queryParameters['company_id'], 'eq.company');
      expect(site.queryParameters['id'], 'eq.site');
    },
  );

  test(
    'known missing company address and inaccessible company are different',
    () async {
      role = 'owner';
      final repository = HomeWeatherLocationRepository.forTesting(client);
      final missing = await repository.load(const HomeAttendanceStatus());
      expect(missing.companyAddressMissing, isTrue);
      expect(missing.selection.kind, WeatherAddressKind.unavailable);
      expect(
        requests.where(
          (uri) => uri.path.endsWith('current_worker_personnel_profile'),
        ),
        isEmpty,
      );
      companyVisible = false;
      await expectLater(
        repository.load(const HomeAttendanceStatus()),
        throwsStateError,
      );
    },
  );
}

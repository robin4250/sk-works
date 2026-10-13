import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/daily_reports/daily_report_repository.dart';

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'responsible lookup uses exact selected site or route, never first registered name',
    () => HttpOverrides.runWithHttpOverrides(() async {
      final requests = <Uri>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        await request.drain<void>();
        requests.add(request.uri);
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path.endsWith('site_directory_rows_v2')) {
          request.response.write(
            jsonEncode([
              {'id': 'other-site', 'manager_name': '別現場の責任者'},
              {'id': 'selected-site', 'manager_name': '  現場登録責任者  '},
              {'id': 'empty-site', 'manager_name': ''},
            ]),
          );
        } else {
          expect(request.uri.queryParameters['id'], 'eq.selected-route');
          expect(request.uri.queryParameters['select'], 'responsible_name');
          request.response.write(jsonEncode({'responsible_name': 'ルート登録責任者'}));
        }
        await request.response.close();
      });
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'synthetic-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(() async {
        await client.dispose();
        await server.close(force: true);
      });
      final repository = DailyReportRepository.forTesting(client);
      expect(
        await repository.loadResponsibleName(siteId: 'selected-site'),
        '現場登録責任者',
      );
      expect(await repository.loadResponsibleName(siteId: 'empty-site'), '');
      expect(
        await repository.loadResponsibleName(siteId: 'not-visible-site'),
        '',
      );
      expect(
        await repository.loadResponsibleName(
          routeAssignmentId: 'selected-route',
        ),
        'ルート登録責任者',
      );
      expect(await repository.loadResponsibleName(), '');
      expect(requests.length, 4);
    }, _RealHttpOverrides()),
  );
}

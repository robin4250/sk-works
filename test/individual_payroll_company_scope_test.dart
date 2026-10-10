import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/individual_payroll_settings_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const workerId = '10000000-0000-0000-0000-000000000001';
  const companyId = '10000000-0000-0000-0000-000000000002';
  late HttpServer server;
  late SupabaseClient client;
  late IndividualPayrollSettingsRepository repository;
  final requests = <Uri>[];
  var hasSettings = true;
  var workerVisible = true;

  setUp(() async {
    requests.clear();
    hasSettings = true;
    workerVisible = true;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests.add(request.uri);
      expect(request.method, 'GET');
      Object response;
      if (request.uri.path == '/rest/v1/worker_payroll_settings') {
        expect(request.uri.queryParameters['worker_id'], 'eq.$workerId');
        response = hasSettings ? [{
          'worker_id': workerId, 'company_id': companyId,
          'day_daily': 12345, 'resident_tax_monthly': 26000,
        }] : [];
      } else if (request.uri.path == '/rest/v1/workers') {
        expect(request.uri.queryParameters['id'], 'eq.$workerId');
        expect(request.uri.queryParameters['select'], 'company_id');
        response = workerVisible ? [{'company_id': companyId}] : [];
      } else {
        request.response.statusCode = 404;
        response = {'message': 'unexpected synthetic request'};
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(response));
      await request.response.close();
    });
    client = SupabaseClient('http://127.0.0.1:${server.port}', 'synthetic-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false));
    repository = IndividualPayrollSettingsRepository.forTesting(client);
  });
  tearDown(() async {
    await client.dispose();
    await server.close(force: true);
  });

  test('existing settings retain company and all salary values without extra lookup', () async {
    final setting = await repository.loadSetting(workerId);
    expect(setting.values['company_id'], companyId);
    expect(setting.amount('day_daily'), 12345);
    expect(setting.amount('resident_tax_monthly'), 26000);
    expect(requests, hasLength(1));
  });

  test('unsaved worker resolves its own company without creating salary data', () async {
    hasSettings = false;
    final setting = await repository.loadSetting(workerId);
    expect(setting.values, {'company_id': companyId});
    expect(requests, hasLength(2));
  });

  test('RLS-hidden worker never borrows another company', () async {
    hasSettings = false;
    workerVisible = false;
    final setting = await repository.loadSetting(workerId);
    expect(setting.values, isEmpty);
    expect(requests, hasLength(2));
  });
}

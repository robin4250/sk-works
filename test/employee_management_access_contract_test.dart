import 'dart:io';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/people/people_cloud_repository.dart';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('employee pages permit read-only viewers while management writes remain restricted', () {
    final app = File('lib/app_v2.dart').readAsStringSync();
    final repository = File(
      'lib/features/people/people_cloud_repository.dart',
    ).readAsStringSync();
    final migration = File(
      'supabase/migrations/20261002011817_add_employee_personnel_rows.sql',
    ).readAsStringSync();

    expect(app, contains("key == 'people' && !_identity.isManagement && !_isViewer"));
    expect(
      app,
      contains("'社員情報は管理者・閲覧者・サブ管理者が閲覧できます'"),
    );
    expect(repository, contains("member.role == 'viewer'"));
    expect(repository, contains("await _requireManagePeople();"));
    expect(repository, contains("'employee_personnel_view'"));
    expect(repository, contains("member.role == 'owner'"));
    expect(repository, contains("member.role == 'admin'"));
    expect(repository, contains("readPersonnel(expectedCompany:companyId)"));
    expect(
      migration,
      contains("cm.role::text in ('owner','admin','manager')"),
    );
  });
  test('scoped canonical permission preserves owner admin delegated manager and read-only viewer', () async {
    for (final role in ['owner', 'admin', 'manager', 'viewer']) {
      final client = SupabaseClient('https://personnel-contract.invalid', 'fixture-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          Object response;
          if (request.url.path.endsWith('/company_members')) {
            expect(request.url.queryParameters['company_id'], 'eq.company-b');
            response = [{'company_id': 'company-b', 'role': role}];
          } else {
            expect(request.url.path, '/rest/v1/rpc/employee_personnel_view');
            expect(jsonDecode(request.body), {'p_company': 'company-b'});
            response = {'company_id': 'company-b', 'records': [
              {'id': 'worker-b', 'active': true, 'address': 'retained address',
               'familyMembers': [{'name': 'retained family'}]},
            ]};
          }
          return http.Response(jsonEncode(response), 200,
            request: request, headers: {'content-type': 'application/json'});
        }));
      final repository = PeopleCloudRepository.forTesting(client, actor: () => 'actor');
      final snapshot = await repository.readPersonnel(expectedCompany: 'company-b');
      expect(snapshot.company, 'company-b');
      expect(snapshot.canManage, role != 'viewer');
      expect(snapshot.records.single['address'], 'retained address');
      expect(await repository.canManagePeople(companyId: 'company-b'), role != 'viewer');
      expect(await repository.canViewPeople(companyId: 'company-b'), true);
      await client.dispose();
    }
  });

  test('manager role alone cannot override canonical feature denial', () async {
    final client = SupabaseClient('https://personnel-contract.invalid', 'fixture-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/company_members')) {
          return http.Response(jsonEncode([{'company_id': 'company-b', 'role': 'manager'}]),
            200, request: request, headers: {'content-type': 'application/json'});
        }
        expect(request.url.path, '/rest/v1/rpc/employee_personnel_view');
        expect(jsonDecode(request.body), {'p_company': 'company-b'});
        return http.Response(jsonEncode({'code': '42501', 'message': 'denied'}),
          403, request: request, headers: {'content-type': 'application/json'});
      }));
    final repository = PeopleCloudRepository.forTesting(client, actor: () => 'actor');
    expect(await repository.canManagePeople(companyId: 'company-b'), false);
    expect(await repository.canViewPeople(companyId: 'company-b'), false);
    await expectLater(repository.readPersonnel(expectedCompany: 'company-b'),
      throwsA(isA<PostgrestException>().having((error) => error.code, 'permission', '42501')));
    await client.dispose();
  });
}

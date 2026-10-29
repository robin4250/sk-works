import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sk_works/features/people/employee_retirement_repository.dart';
import 'package:sk_works/features/people/employee_retirement_page.dart';
import 'package:sk_works/features/people/people_page.dart';
import 'app_auth_mutation_gateway_test.dart' as fixture;

const company = '60000000-0000-0000-0000-000000000010';
const worker = '60000000-0000-0000-0000-000000000020';
class FakeRetirement extends EmployeeRetirementRepository {
  FakeRetirement(super.client);
  int writes = 0;
  @override Future<void> retire({required String companyId, required String workerId}) async { writes++; }
}
void main() {
  late fixture.Wire w;
  late String role;
  late bool active;
  late List<http.Request> writes;
  setUp(() async {
    w = fixture.Wire(); await w.seed(); role = 'admin'; active = true; writes = [];
    w.respond = (request) async {
      if (request.url.path.endsWith('/company_members')) return fixture.Wire.json([{'company_id': company, 'role': role}]);
      if (request.url.path.endsWith('/rpc/employee_personnel_view')) return fixture.Wire.json({
        'company_id': company, 'records': [{'id': worker, 'kind': 'employee', 'name': 'Fixture', 'active': true}]});
      if (request.url.path.endsWith('/workers')) {
        if (request.method == 'PATCH') { writes.add(request); active = false; }
        return fixture.Wire.json([{'id': worker, 'company_id': company, 'status': active ? 'active' : 'inactive'}]);
      }
      throw StateError('Unexpected fixture endpoint');
    };
  });
  tearDown(() async { await w.client.dispose(); });

  test('only status changes using exact company/id/active CAS and captured bearer', () async {
    final token = w.client.auth.currentSession!.accessToken;
    await EmployeeRetirementRepository(w.client).retire(companyId: company, workerId: worker);
    expect(writes, hasLength(1));
    expect(jsonDecode(writes.single.body), {'status': 'inactive'});
    expect(writes.single.url.queryParameters['company_id'], 'eq.$company');
    expect(writes.single.url.queryParameters['id'], 'eq.$worker');
    expect(writes.single.url.queryParameters['status'], 'eq.active');
    expect(writes.single.headers['Authorization'], 'Bearer $token');
    expect(w.calls.any((r) => r.method == 'DELETE'), isFalse);
    expect(w.calls.where((r) => r.url.path.endsWith('/workers') && r.method == 'GET'), hasLength(1));
  });
  test('viewer cannot issue status write', () async {
    role = 'viewer';
    await expectLater(EmployeeRetirementRepository(w.client).retire(companyId: company, workerId: worker), throwsStateError);
    expect(writes, isEmpty);
  });
  test('session boundary during permission read rejects before status write', () async {
    final old = w.respond; final ready = Completer<void>(), release = Completer<void>();
    w.respond = (request) async {
      if (request.url.path.endsWith('/rpc/employee_personnel_view')) { ready.complete(); await release.future; }
      return old(request);
    };
    final outcome = expectLater(EmployeeRetirementRepository(w.client).retire(companyId: company, workerId: worker), throwsA(anything));
    await ready.future; await w.seed(sessionId: fixture.nextSid); release.complete();
    await outcome; expect(writes, isEmpty);
  });
  test('CAS zero rows fails without retry or delete', () async {
    final old = w.respond;
    w.respond = (request) async => request.method == 'PATCH' ? fixture.Wire.json([]) : old(request);
    await expectLater(EmployeeRetirementRepository(w.client).retire(companyId: company, workerId: worker), throwsStateError);
    expect(w.calls.where((r) => r.method == 'PATCH'), hasLength(1));
  });
  test('label changes without changing stored partnerWorker value', () {
    expect(PersonKind.partnerWorker.label, '協力会社従業員');
    expect(const PersonRecord(id: worker, kind: PersonKind.partnerWorker, name: 'Fixture').toJson()['kind'], 'partnerWorker');
  });
  testWidgets('retirement requires explicit confirmation', (tester) async {
    final repo = FakeRetirement(w.client);
    await tester.pumpWidget(MaterialApp(home: EmployeeRetirementPage(companyId: company,
      workerId: worker, workerName: 'Fixture', repository: repo)));
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    await tester.tap(find.byType(CheckboxListTile)); await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
    expect(repo.writes, 0);
    expect(find.textContaining('削除しません'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

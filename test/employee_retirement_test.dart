import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sk_works/features/people/employee_retirement_repository.dart';
import 'package:sk_works/features/people/employee_retirement_page.dart';
import 'package:sk_works/features/people/people_page.dart';
import 'package:sk_works/features/people/people_cloud_repository.dart';
import 'app_auth_mutation_gateway_test.dart' as fixture;

const company = '60000000-0000-0000-0000-000000000010';
const worker = '60000000-0000-0000-0000-000000000020';

class FakeRetirement extends EmployeeRetirementRepository {
  FakeRetirement(super.client);
  int writes = 0;
  @override
  Future<RetirementQueueState> queueState({required String companyId, required String workerId,
    required void Function() verifyContext}) async {
    verifyContext();
    return RetirementQueueState.none;
  }

  @override
  Future<void> retire({
    required String companyId,
    required String workerId,
    required void Function() verifyContext,
  }) async {
    verifyContext();
    writes++;
  }
}

void main() {
  late fixture.Wire w;
  late String role;
  late List<http.Request> writes;
  setUp(() async {
    w = fixture.Wire();
    await w.seed();
    role = 'admin';
    writes = [];
    w.respond = (request) async {
      if (request.url.path.endsWith('/company_members')) {
        return fixture.Wire.json([
          {'company_id': company, 'role': role},
        ]);
      }
      if (request.url.path.endsWith('/rpc/employee_personnel_view')) {
        return fixture.Wire.json({
          'company_id': company,
          'records': [
            {
              'id': worker,
              'kind': 'employee',
              'name': 'Fixture',
              'active': true,
            },
          ],
        });
      }
      if (request.url.path.endsWith('/rpc/retirement_render_state_pilot')) {
        return fixture.Wire.json('none');
      }
      if (request.url.path.endsWith('/rpc/request_retirement_render_pilot')) {
        writes.add(request);
        return fixture.Wire.json('60000000-0000-0000-0000-000000000030');
      }
      throw StateError('Unexpected fixture endpoint');
    };
  });
  tearDown(() async {
    await w.client.dispose();
  });

  test(
    'queues retirement under the captured account without touching workers',
    () async {
      final token = w.client.auth.currentSession!.accessToken;
      await expectLater(
        EmployeeRetirementRepository(
          w.client,
        ).retire(companyId: company, workerId: worker, verifyContext: () {}),
        throwsA(isA<RetirementQueued>()),
      );
      expect(writes, hasLength(1));
      expect(jsonDecode(writes.single.body), {
        'p_company': company,
        'p_worker': worker,
      });
      expect(writes.single.headers['Authorization'], 'Bearer $token');
      expect(
        w.calls.any((r) => r.method == 'DELETE' || r.method == 'PATCH'),
        isFalse,
      );
    },
  );
  test('viewer cannot issue status write', () async {
    role = 'viewer';
    await expectLater(
      EmployeeRetirementRepository(
        w.client,
      ).retire(companyId: company, workerId: worker, verifyContext: () {}),
      throwsStateError,
    );
    expect(writes, isEmpty);
  });
  test(
    'session boundary during permission read rejects before status write',
    () async {
      final old = w.respond;
      final ready = Completer<void>(), release = Completer<void>();
      w.respond = (request) async {
        if (request.url.path.endsWith('/rpc/employee_personnel_view')) {
          ready.complete();
          await release.future;
        }
        return old(request);
      };
      final outcome = expectLater(
        EmployeeRetirementRepository(
          w.client,
        ).retire(companyId: company, workerId: worker, verifyContext: () {}),
        throwsA(anything),
      );
      await ready.future;
      await w.seed(sessionId: fixture.nextSid);
      release.complete();
      await outcome;
      expect(writes, isEmpty);
    },
  );
  test(
    'page lease invalidation during permission read prevents dispatch',
    () async {
      final old = w.respond;
      final ready = Completer<void>(), release = Completer<void>();
      var valid = true;
      w.respond = (request) async {
        if (request.url.path.endsWith('/rpc/employee_personnel_view')) {
          ready.complete();
          await release.future;
        }
        return old(request);
      };
      final outcome = expectLater(
        EmployeeRetirementRepository(w.client).retire(
          companyId: company,
          workerId: worker,
          verifyContext: () {
            if (!valid) throw const PersonnelScopeChanged();
          },
        ),
        throwsA(isA<PersonnelScopeChanged>()),
      );
      await ready.future;
      valid = false;
      release.complete();
      await outcome;
      expect(writes, isEmpty);
    },
  );
  test('invalid queue response stops without retry or worker update', () async {
    final old = w.respond;
    w.respond = (request) async {
      if (request.url.path.endsWith('/rpc/request_retirement_render_pilot')) {
        return fixture.Wire.json(false);
      }
      return old(request);
    };
    await expectLater(
      EmployeeRetirementRepository(
        w.client,
      ).retire(companyId: company, workerId: worker, verifyContext: () {}),
      throwsStateError,
    );
    expect(
      w.calls.where(
        (r) => r.url.path.endsWith('/rpc/request_retirement_render_pilot'),
      ),
      hasLength(1),
    );
    expect(w.calls.any((r) => r.method == 'PATCH'), isFalse);
  });
  test('label changes without changing stored partnerWorker value', () {
    expect(PersonKind.partnerWorker.label, '協力会社従業員');
    expect(
      const PersonRecord(
        id: worker,
        kind: PersonKind.partnerWorker,
        name: 'Fixture',
      ).toJson()['kind'],
      'partnerWorker',
    );
  });
  testWidgets('retirement requires explicit confirmation', (tester) async {
    final repo = FakeRetirement(w.client);
    final privacy = PersonnelPrivacySession(
      actor: fixture.actor,
      company: company,
      currentActor: () => fixture.actor,
      load: () async => throw UnimplementedError(),
    );
    privacy.snapshot = const PersonnelPrivacySnapshot(
      actor: fixture.actor,
      company: company,
      role: 'admin',
      canManage: true,
      records: [
        {'id': worker, 'active': true},
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: EmployeeRetirementPage(
          companyId: company,
          workerId: worker,
          workerName: 'Fixture',
          privacySession: privacy,
          repository: repo,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    expect(repo.writes, 0);
    expect(find.textContaining('削除しません'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    privacy.dispose();
  });
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sk_works/features/people/employee_initial_registration_page.dart';
import 'package:sk_works/features/people/employee_invite_page.dart';
import 'package:sk_works/features/people/employee_invite_repository.dart';

const actor = '10000000-0000-0000-0000-000000000001';
const company = '30000000-0000-0000-0000-000000000001';
const worker = '40000000-0000-0000-0000-000000000001';
const authUser = '50000000-0000-0000-0000-000000000001';
const invite = '70000000-0000-0000-0000-000000000001';
const sid = '80000000-0000-0000-0000-000000000001';
const nextSid = '80000000-0000-0000-0000-000000000002';
const fixturePassword = 'synthetic-private-credential';

String token(String session) {
  String part(Object v) =>
      base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
  return '${part({'alg': 'ES256'})}.${part({'sub': actor, 'role': 'authenticated', 'session_id': session, 'exp': 4102444800})}.synthetic';
}

Map<String, dynamic> result() => {
  'actorId': actor,
  'sessionId': sid,
  'companyId': company,
  'workerId': worker,
  'authUserId': authUser,
  'inviteId': invite,
  'name': 'Synthetic Employee',
  'phone': '+817000000000',
  'temporaryPassword': fixturePassword,
  'smsSent': false,
  'qrPayload': jsonEncode({
    'type': 'sko_employee_invite',
    'inviteId': invite,
    'phone': '+817000000000',
    'password': fixturePassword,
  }),
};

class ObservedInviteRepository extends EmployeeInviteRepository {
  ObservedInviteRepository(super.client);
  final completed = Completer<void>();
  final refreshed = Completer<void>();
  int employeeLoads = 0, urlLoads = 0;
  void _loaded() {
    if (employeeLoads >= 2 && !refreshed.isCompleted) {
      refreshed.complete();
      debugPrint('invite-ui actual post-create refresh completed');
    }
  }

  @override
  Future<List<InitialRegistrationEmployee>> loadRegisteredEmployees({
    EmployeeInviteRequest? request,
  }) async {
    final value = await super.loadRegisteredEmployees(request: request);
    employeeLoads++;
    _loaded();
    return value;
  }

  @override
  Future<String> loadTestFlightUrl({EmployeeInviteRequest? request}) async {
    final value = await super.loadTestFlightUrl(request: request);
    urlLoads++;
    _loaded();
    return value;
  }

  Future<EmployeeInviteResult> _observe(
    Future<EmployeeInviteResult> operation,
  ) async {
    try {
      return await operation;
    } finally {
      if (!completed.isCompleted) completed.complete();
      debugPrint('invite-sdk operation completed');
    }
  }

  @override
  Future<EmployeeInviteResult> createInvite({
    required String name,
    required String phone,
    String requestedRole = 'viewer',
    bool requestedApprovalAssignee = false,
    String? replaceApprovalAssigneeUserId,
    EmployeeInviteRequest? request,
  }) => _observe(
    super.createInvite(
      name: name,
      phone: phone,
      requestedRole: requestedRole,
      requestedApprovalAssignee: requestedApprovalAssignee,
      replaceApprovalAssigneeUserId: replaceApprovalAssigneeUserId,
      request: request,
    ),
  );
  @override
  Future<EmployeeInviteResult> createInviteForWorker(
    String workerId, {
    required String expectedPhone,
    bool deliverSms = true,
    EmployeeInviteRequest? request,
  }) => _observe(
    super.createInviteForWorker(
      workerId,
      expectedPhone: expectedPhone,
      deliverSms: deliverSms,
      request: request,
    ),
  );
}

class Fixture {
  Fixture() {
    client = SupabaseClient(
      'https://invite-fixture.invalid',
      'public_fixture',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        debugPrint('invite-sdk fixture request: ${request.url.path}');
        if (request.url.path == '/auth/v1/token') {
          return http.Response(
            jsonEncode({
              'access_token': token(session),
              'refresh_token': 'synthetic-refresh',
              'token_type': 'bearer',
              'expires_in': 3600,
              'user': {
                'id': actor,
                'aud': 'authenticated',
                'created_at': '2026-10-31T00:00:00Z',
                'app_metadata': <String, dynamic>{},
                'user_metadata': <String, dynamic>{},
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        if (request.url.path == '/rest/v1/company_members') {
          return http.Response(
            jsonEncode(memberships),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        if (request.url.path ==
            '/rest/v1/rpc/initial_registration_employee_rows') {
          return http.Response(
            jsonEncode([
              {
                'id': worker,
                'name': 'Synthetic Employee',
                'phone': '07000000000',
                'user_id': null,
              },
            ]),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        if (request.url.path ==
            '/rest/v1/rpc/initial_registration_distribution_settings') {
          return http.Response(
            '{"testflight_url":""}',
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        if (request.url.path == '/functions/v1/create-employee-invite') {
          final operation = (jsonDecode(request.body) as Map)['operation'];
          if (operation == 'inspect_context') {
            inspections++;
            final payload = jsonDecode(request.body) as Map;
            expect(payload.keys.toSet(), {
              'operation',
              'companyId',
              'sessionId',
            });
            return http.Response(
              jsonEncode(capability),
              inspectionStatus,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          expect(operation, 'create_bound_v1');
          invokes++;
          if (!issued.isCompleted) issued.complete();
          expect(
            request.headers['Authorization'] == 'Bearer ${token(sid)}',
            isTrue,
            reason: 'captured authorization is retained',
          );
          final body = jsonDecode(request.body) as Map;
          expect(body['companyId'], company);
          expect(body['sessionId'], sid);
          return await (pending?.future ??
              Future.value(
                http.Response(
                  jsonEncode(response),
                  200,
                  headers: {'content-type': 'application/json'},
                  request: request,
                ),
              ));
        }
        throw StateError('Unexpected synthetic request');
      }),
    );
    repository = ObservedInviteRepository(client);
  }
  late final SupabaseClient client;
  late final ObservedInviteRepository repository;
  String session = sid;
  int invokes = 0, inspections = 0, inspectionStatus = 200;
  final issued = Completer<void>();
  Object? capability = {
    'version': 1,
    'capability': 'employee_invite_bound_v1',
    'actorId': actor,
    'companyId': company,
    'sessionId': sid,
  };
  Object response = result();
  Completer<http.Response>? pending;
  List<Object> memberships = [
    {'company_id': company, 'role': 'owner'},
  ];
  final requests = <http.Request>[];
  Future<void> login() async {
    debugPrint('invite-sdk login begin');
    await client.auth.signInWithPassword(
      email: 'fixture@example.invalid',
      password: 'synthetic',
    );
    await Future<void>.delayed(Duration.zero);
    debugPrint('invite-sdk login complete and auth events settled');
  }

  Future<void> close() async {
    await repository.dispose();
    await client.dispose();
  }
}

void main() {
  test('actual pinned SDK uses captured Bearer and exact company/SID and validates returned QR', () async {
    final f = Fixture();
    addTearDown(f.close);
    await f.login();
    try {
      final probe = await f.client
          .from('company_members')
          .select('company_id,role')
          .retry(enabled: false);
      expect(probe.length, 1);
      debugPrint('invite-sdk transport probe complete');
    } catch (error, stack) {
      debugPrint('invite-sdk transport type ${error.runtimeType}');
      debugPrint(stack.toString().split('\n').take(4).join('\n'));
      throw StateError('Synthetic membership transport did not complete');
    }
    final context = await f.repository.beginRequest();
    final value = await f.repository.createInvite(
      name: 'Synthetic Employee',
      phone: '07000000000',
      request: context,
    );
    expect(value.inviteId, invite);
    expect(value.temporaryPassword, fixturePassword);
    expect(f.invokes, 1);
  });

  final validCapability = {
    'version': 1,
    'capability': 'employee_invite_bound_v1',
    'actorId': actor,
    'companyId': company,
    'sessionId': sid,
  };
  final invalidCapabilities = <String, Object?>{
    'missing': <String, dynamic>{},
    'legacy-response': result(),
    'legacy-http': {'error': 'upgrade required'},
    'null': null,
    'array': [],
    'version-type': {...validCapability, 'version': '1'},
    'old-capability': {...validCapability, 'capability': 'legacy'},
    'actor': {...validCapability, 'actorId': worker},
    'company': {...validCapability, 'companyId': worker},
    'session': {...validCapability, 'sessionId': nextSid},
    'extra-code': {...validCapability, 'code': 'failed'},
    'extra-error': {...validCapability, 'error': 'failed'},
    'extra-key': {...validCapability, 'unknown': true},
  };
  for (final entry in invalidCapabilities.entries) {
    test('capability ${entry.key} never starts create', () async {
      final f = Fixture();
      addTearDown(f.close);
      await f.login();
      f.capability = entry.value;
      if (entry.key == 'legacy-http') f.inspectionStatus = 400;
      final context = await f.repository.beginRequest();
      await expectLater(
        f.repository.createInvite(
          name: 'Synthetic',
          phone: '07000000000',
          request: context,
        ),
        throwsA(anything),
      );
      expect(f.inspections, 1);
      expect(f.invokes, 0);
    });
  }

  test(
    'ambiguous membership and malformed row fail before invoking issuer',
    () async {
      for (final rows in <List<Object>>[
        [],
        [
          {'company_id': company, 'role': 'owner'},
          {'company_id': worker, 'role': 'owner'},
        ],
        ['invalid'],
        [
          {'company_id': company, 'role': 'invented'},
        ],
      ]) {
        final f = Fixture();
        await f.login();
        f.memberships = rows;
        await expectLater(f.repository.beginRequest(), throwsStateError);
        expect(f.invokes, 0);
        await f.close();
      }
    },
  );

  for (final invalid in [
    'empty',
    'missing',
    'qr-phone',
    'qr-invite',
    'qr-password',
    'company',
    'session',
    'worker',
  ]) {
    test(
      'malformed success $invalid stays unresolved and does not recreate canonical recipient',
      () async {
        final f = Fixture();
        addTearDown(f.close);
        await f.login();
        final value = result();
        switch (invalid) {
          case 'empty':
            f.response = <String, dynamic>{};
          case 'missing':
            value.remove('temporaryPassword');
            f.response = value;
          case 'qr-phone':
          case 'qr-invite':
          case 'qr-password':
            final qr = jsonDecode(value['qrPayload'] as String) as Map;
            qr[invalid.substring(3) == 'invite'
                    ? 'inviteId'
                    : invalid.substring(3)] =
                'mismatched';
            value['qrPayload'] = jsonEncode(qr);
            f.response = value;
          case 'company':
            value['companyId'] = worker;
            f.response = value;
          case 'session':
            value['sessionId'] = nextSid;
            f.response = value;
          case 'worker':
            value['workerId'] = 'invalid';
            f.response = value;
        }
        final context = await f.repository.beginRequest();
        await expectLater(
          f.repository.createInvite(
            name: 'Synthetic',
            phone: '07000000000',
            request: context,
          ),
          throwsStateError,
        );
        await expectLater(
          f.repository.createInvite(
            name: 'Synthetic',
            phone: '+81 70-0000-0000',
            request: context,
          ),
          throwsStateError,
        );
        expect(f.invokes, 1);
      },
    );
  }

  test('same actor SID ABA retires a late result and never reuses new ambient Bearer', () async {
    final f = Fixture();
    addTearDown(f.close);
    await f.login();
    final context = await f.repository.beginRequest();
    f.pending = Completer<http.Response>();
    final creation = f.repository.createInviteForWorker(
      worker,
      expectedPhone: '07000000000',
      request: context,
    );
    await f.issued.future;
    f.session = nextSid;
    await f.login();
    f.session = sid;
    await f.login();
    f.pending!.complete(
      http.Response(
        jsonEncode(result()),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    await expectLater(creation, throwsStateError);
    expect(context.isCurrent, isFalse);
    expect(f.invokes, 1);
  });

  testWidgets(
    'new employee page hides credentials immediately after same-user new SID',
    (tester) async {
      final f = (await tester.runAsync(() async => Fixture()))!;
      debugPrint('invite-ui SDK constructed in real async zone');
      addTearDown(() async {
        await tester.runAsync(f.close);
      });
      await tester.runAsync(f.login);
      await tester.pumpWidget(
        MaterialApp(home: EmployeeInvitePage(repository: f.repository)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).at(0),
        'Synthetic Employee',
      );
      await tester.enterText(find.byType(TextField).at(1), '07000000000');
      final create = find.byWidgetPredicate((w) => w is FilledButton);
      await tester.ensureVisible(create.first);
      await tester.runAsync(() async {
        await tester.tap(create.first);
        await f.repository.completed.future;
      });
      await tester.pumpAndSettle();
      expect(find.text(fixturePassword), findsOneWidget);
      f.session = nextSid;
      await tester.runAsync(f.login);
      await tester.pumpAndSettle();
      expect(find.text(fixturePassword), findsNothing);
      expect(find.text('ログイン状態または会社が変わりました。画面を開き直してください。'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'existing worker page hides QR/password after same-user new SID',
    (tester) async {
      final f = (await tester.runAsync(() async => Fixture()))!;
      debugPrint('invite-ui SDK constructed in real async zone');
      addTearDown(() async {
        await tester.runAsync(f.close);
      });
      await tester.runAsync(f.login);
      await tester.pumpWidget(
        MaterialApp(
          home: EmployeeInitialRegistrationPage(repository: f.repository),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('送信'));
      await tester.runAsync(() async {
        await tester.tap(find.text('送信'));
        await f.repository.completed.future;
        await f.repository.refreshed.future;
      });
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('初期パスワード: $fixturePassword'),
        200,
        maxScrolls: 20,
        scrollable: find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('初期パスワード: $fixturePassword'), findsOneWidget);
      f.session = nextSid;
      await tester.runAsync(f.login);
      await tester.pumpAndSettle();
      expect(find.text('初期パスワード: $fixturePassword'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}


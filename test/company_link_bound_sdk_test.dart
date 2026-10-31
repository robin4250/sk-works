import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/companies/trade_company_repository.dart';
import 'package:sk_works/features/companies/company_link_page.dart';

const actor = '10000000-0000-0000-0000-000000000001';
const company = '20000000-0000-0000-0000-000000000001';
const sid = '30000000-0000-0000-0000-000000000001';
const sid2 = '30000000-0000-0000-0000-000000000002';
String token(String session) {
  String part(Object v) =>
      base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
  return '${part({'alg': 'ES256'})}.${part({'sub': actor, 'session_id': session, 'role': 'authenticated'})}.synthetic';
}

class Fixture {
  Fixture() {
    client = SupabaseClient(
      'https://company-link-fixture.invalid',
      'public_fixture',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        Object? value;
        if (request.url.path == '/auth/v1/token') {
          value = {
            'access_token': token(session),
            'refresh_token': 'synthetic-refresh',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': {
              'id': actor,
              'aud': 'authenticated',
              'created_at': '2026-10-31T00:00:00Z',
              'app_metadata': {},
              'user_metadata': {},
            },
          };
        } else if (request.url.path == '/rest/v1/company_members') {
          value = memberships;
        } else if (request.url.path == '/rest/v1/rpc/company_link_bound_v1') {
          final body = jsonDecode(request.body) as Map;
          final command = body['p_command'];
          if (command == 'set_enabled') {
            mutations++;
            saved = Map<String, dynamic>.from(body);
            if (!arrived.isCompleted) arrived.complete();
            if (pending != null) return pending!.future;
            if (loseAck) {
              throw http.ClientException('synthetic acknowledgement loss');
            }
          }
          final result = command == 'workspace'
              ? {'enabled': true, 'requests': workspaceRows}
              : command == 'result'
              ? {
                  'state': 'committed',
                  'command': saved!['p_command'],
                  'original_session_id': saved!['p_session'],
                  'payload': saved!['p_payload'],
                  'result': {'state': 'committed', 'enabled': true},
                }
              : {'state': 'committed', 'enabled': true};
          value = envelope(body, result);
          if (command == 'workspace' && !workspaceLoaded.isCompleted)
            workspaceLoaded.complete();
          if (badEnvelope) (value as Map)['company_id'] = sid2;
        } else {
          throw StateError('unexpected synthetic path');
        }
        return http.Response(
          jsonEncode(value),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    repository = TradeCompanyRepository.forTesting(client);
  }
  late final SupabaseClient client;
  late final TradeCompanyRepository repository;
  String session = sid;
  final requests = <http.Request>[];
  List<Object> memberships = [
    {'company_id': company, 'role': 'admin'},
  ];
  bool loseAck = false, badEnvelope = false;
  int mutations = 0;
  Map<String, dynamic>? saved;
  Completer<http.Response>? pending;
  final arrived = Completer<void>();
  final workspaceLoaded = Completer<void>();
  List<Map<String, dynamic>> workspaceRows = [];
  Map<String, dynamic> envelope(Map body, Object value) => {
    'version': 1,
    'actor_id': actor,
    'company_id': body['p_company'],
    'session_id': body['p_session'],
    'operation_id': body['p_operation'],
    'command': body['p_command'],
    'value': value,
  };
  Future<void> login() async {
    await client.auth.signInWithPassword(
      email: 'fixture@example.invalid',
      password: 'synthetic',
    );
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('actual SDK uses explicit sender tuple and bearer', () async {
    final f = Fixture();
    addTearDown(f.client.dispose);
    await f.login();
    final context = await f.repository.openBoundLinkContext();
    addTearDown(context.dispose);
    expect((await context.workspace())['enabled'], true);
    await context.mutate('set_enabled', {'enabled': true});
    final request = f.requests.last;
    expect(request.headers['Authorization'], 'Bearer ${token(sid)}');
    final body = jsonDecode(request.body) as Map;
    expect(body['p_company'], company);
    expect(body['p_session'], sid);
    expect(f.mutations, 1);
    expect(context.hasUnknownResult, false);
  });
  test('multiple memberships fail before company-link RPC', () async {
    final f = Fixture();
    addTearDown(f.client.dispose);
    await f.login();
    f.memberships.add({'company_id': sid2, 'role': 'admin'});
    await expectLater(f.repository.openBoundLinkContext(), throwsStateError);
    expect(f.requests.where((r) => r.url.path.contains('/rpc/')), isEmpty);
  });
  test('lost ACK is never retried and safe IDs recover after route restart/new SID', () async {
    final f = Fixture();
    addTearDown(f.client.dispose);
    await f.login();
    final first = await f.repository.openBoundLinkContext();
    f.loseAck = true;
    await expectLater(
      first.mutate('set_enabled', {'enabled': true}),
      throwsA(anything),
    );
    expect(f.mutations, 1);
    await first.dispose();
    f.session = sid2;
    await f.login();
    final second = await f.repository.openBoundLinkContext();
    addTearDown(second.dispose);
    expect(second.hasUnknownResult, true);
    await expectLater(
      second.mutate('set_enabled', {'enabled': true}),
      throwsStateError,
    );
    expect((await second.inspectUnknownResult())['state'], 'committed');
    expect(f.mutations, 1);
    expect(second.hasUnknownResult, false);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty);
  });
  test(
    'malformed successful envelope keeps unknown record and blocks mutation',
    () async {
      final f = Fixture();
      addTearDown(f.client.dispose);
      await f.login();
      final context = await f.repository.openBoundLinkContext();
      addTearDown(context.dispose);
      f.badEnvelope = true;
      await expectLater(
        context.mutate('set_enabled', {'enabled': true}),
        throwsStateError,
      );
      expect(context.hasUnknownResult, true);
      await expectLater(
        context.mutate('set_enabled', {'enabled': false}),
        throwsStateError,
      );
      expect(f.mutations, 1);
    },
  );
  test(
    'same actor SID ABA permanently rejects late company-link receipt',
    () async {
      final f = Fixture();
      addTearDown(f.client.dispose);
      await f.login();
      final context = await f.repository.openBoundLinkContext();
      addTearDown(context.dispose);
      f.pending = Completer<http.Response>();
      final result = context.mutate('set_enabled', {'enabled': true});
      final rejected = expectLater(result, throwsStateError);
      await f.arrived.future;
      f.session = sid2;
      await f.login();
      f.session = sid;
      await f.login();
      f.pending!.complete(
        http.Response(
          jsonEncode(
            f.envelope(f.saved!, {'state': 'committed', 'enabled': true}),
          ),
          200,
          headers: {'content-type': 'application/json'},
          request: f.requests.firstWhere(
            (r) => r.url.path.endsWith('company_link_bound_v1'),
          ),
        ),
      );
      await rejected;
      expect(context.isCurrent, false);
      expect(context.hasUnknownResult, true);
    },
  );
  for (final change in ['sid', 'background', 'repository', 'mode', 'request']) {
    testWidgets('open approval dialog masks old company on $change change', (
      tester,
    ) async {
      final f = (await tester.runAsync(() async {
        final value = Fixture();
        await value.login();
        return value;
      }))!;
      addTearDown(f.client.dispose);
      f.workspaceRows = [
        {
          'id': '40000000-0000-0000-0000-000000000001',
          'incoming': true,
          'company_id': sid2,
          'company_name': 'Synthetic Partner',
          'start_month': '2026-10-01',
          'status': 'pending',
          'created_at': '2026-10-31',
          'local_role': 'customer',
        },
      ];
      TradeCompanyRepository repo = f.repository;
      TradeCompanyPageMode mode = TradeCompanyPageMode.customer;
      String? initial;
      Widget page() => MaterialApp(
        home: CompanyLinkPage(
          key: const ValueKey('same-route'),
          repository: repo,
          mode: mode,
          initialRequestId: initial,
        ),
      );
      await tester.pumpWidget(page());
      await tester.runAsync(() => f.workspaceLoaded.future);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('承認'));
      await tester.tap(find.text('承認'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Synthetic Partner'), findsWidgets);
      if (change == 'sid') {
        f.session = sid2;
        await tester.runAsync(f.login);
      } else if (change == 'background') {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
      } else {
        if (change == 'repository')
          repo = TradeCompanyRepository.forTesting(f.client);
        if (change == 'mode') mode = TradeCompanyPageMode.subcontractor;
        if (change == 'request')
          initial = '40000000-0000-0000-0000-000000000001';
        await tester.pumpWidget(page());
      }
      await tester.pumpAndSettle();
      expect(find.textContaining('Synthetic Partner'), findsNothing);
      expect(find.text('確認'), findsNothing);
      expect(find.text('表示条件が変わりました'), findsOneWidget);
      expect(f.mutations, 0);
      await tester.tap(find.text('閉じる'));
      await tester.pumpAndSettle();
      expect(find.text('承認'), findsNothing);
      if (change == 'background')
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      await tester.pumpWidget(const SizedBox());
    });
  }
}

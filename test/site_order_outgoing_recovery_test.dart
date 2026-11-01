import 'site_workflow_capability_fixture.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/sites/site_order_outgoing_journal.dart';
import 'package:sk_works/features/sites/site_order_outgoing_recovery_page.dart';
import 'package:sk_works/features/sites/site_order_workflow_repository.dart';

String id(int n) =>
    '10000000-0000-0000-0000-${n.toRadixString(16).padLeft(12, '0')}';
final actor = id(1), company = id(2), site = id(3), sid = id(4);
SiteOrderPendingPrepare entry() => SiteOrderPendingPrepare(
  siteId: site,
  documentId: id(5),
  localId: id(6),
  tradeId: id(7),
  requestId: id(8),
  sessionId: sid,
);

class _Wire extends http.BaseClient {
  String state = 'not_observed', role = 'manager';
  int status = 200, calls = 0;
  bool wrongCompany = false, forgedClear = false;
  Map<String, dynamic>? last;
  final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
  Map<String, dynamic> get session {
    String part(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    final token =
        '${part({'alg': 'HS256'})}.${part({'sub': actor, 'session_id': sid, 'role': 'authenticated', 'exp': expiry})}.${part('synthetic-signature')}';
    return {
      'access_token': token,
      'refresh_token': 'synthetic-refresh',
      'expires_in': 3600,
      'expires_at': expiry,
      'token_type': 'bearer',
      'user': {
        'id': actor,
        'aud': 'authenticated',
        'role': 'authenticated',
        'created_at': '2026-01-01T00:00:00Z',
      },
    };
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path == '/rest/v1/rpc/site_order_workflow_capabilities') {
      return supportedSiteWorkflowCapability(request,
          actor: actor, company: company, session: sid, role: role);
    }
    Object body;
    int code = 200;
    if (request.url.path == '/rest/v1/company_members') {
      body = [
        {'company_id': company, 'role': role},
      ];
    } else {
      expect(request.url.path, '/functions/v1/site-order-workflow/outgoing');
      calls++;
      last = jsonDecode((request as http.Request).body) as Map<String, dynamic>;
      expect(last!.keys.toSet(), {
        'action',
        'site_id',
        'document_id',
        'local_id',
        'trade_id',
        'request_id',
        if (last!['action'] == 'retire') 'confirmed',
      });
      code = status;
      body = code == 200
          ? {
              'result': {
                'contract_version': 1,
                'company_id': wrongCompany ? id(99) : company,
                'request_id': id(8),
                'site_id': site,
                'document_id': id(5),
                'local_document_id': id(6),
                'trade_company_id': id(7),
                'operation_state': state,
                'retry_automatically': false,
                'may_prepare_again': false,
                'can_send': false,
                'retired': state == 'retired',
                'journal_clearable': forgedClear || state == 'retired',
                if (state == 'retired') ...{
                  'retirement_id': id(9),
                  'operation_id': null,
                  'verified_prepared_operation': false,
                  'order_cancelled': false,
                },
              },
            }
          : {'error': 'result_unknown'};
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      code,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }
}

Future<(SupabaseClient, SiteOrderWorkflowRepository)> _repository(
  _Wire wire,
) async {
  final client = SupabaseClient(
    'https://synthetic.invalid',
    'synthetic-public',
    httpClient: wire,
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  await client.auth.setInitialSession(jsonEncode(wire.session));
  await client.auth.recoverSession(jsonEncode(wire.session));
  return (client, SiteOrderWorkflowRepository(client));
}

class _RecoveryApi extends SiteOrderWorkflowApi {
  bool expired = false;
  bool failRead = false;
  int reads = 0, stops = 0;
  String result = 'not_observed';
  @override
  bool get invalidated => expired;
  @override
  void requireCurrent() {
    if (expired) throw StateError('expired');
  }

  @override
  Future<void> verify() async => requireCurrent();
  @override
  Future<List<SiteOrderPendingPrepare>> pendingOutgoing(String siteId) async {
    if (failRead) throw StateError('synthetic read failure');
    return [entry()];
  }

  @override
  Future<String> inspectOutgoing(SiteOrderPendingPrepare entry) async {
    reads++;
    return result;
  }

  @override
  Future<String> retireOutgoing(
    SiteOrderPendingPrepare entry, {
    required bool confirmed,
  }) async {
    expect(confirmed, true);
    stops++;
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'ID-only quarantine survives restart and is isolated by actor company site',
    () async {
      final journal = SiteOrderOutgoingJournal();
      await journal.begin(actor, company, entry());
      final reopened = SiteOrderOutgoingJournal();
      expect(
        (await reopened.read(actor, company, site)).single.toJson(),
        entry().toJson(),
      );
      expect(await reopened.read(id(90), company, site), isEmpty);
      expect(await reopened.read(actor, id(90), site), isEmpty);
      expect(await reopened.read(actor, company, id(90)), isEmpty);
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonDecode(prefs.getString(prefs.getKeys().single)!) as Map;
      expect(raw.keys.toSet(), entry().toJson().keys.toSet());
      expect(raw.values.every(SiteOrderPendingPrepare.validId), true);
      await expectLater(
        journal.begin(actor, company, entry()),
        throwsStateError,
      );
    },
  );
  test(
    'malformed stored metadata fails without dropping pending record',
    () async {
      final journal = SiteOrderOutgoingJournal();
      await journal.begin(actor, company, entry());
      final prefs = await SharedPreferences.getInstance();
      final key = prefs.getKeys().single;
      await prefs.setString(
        key,
        jsonEncode({...entry().toJson(), 'body': 'must never persist'}),
      );
      await expectLater(journal.read(actor, company, site), throwsStateError);
      expect(prefs.containsKey(key), true);
    },
  );
  test('RAM draft copies nested content and destroys it permanently on scope retirement', () {
    final body = <String, dynamic>{
      'price': 12,
      'nested': {'name': 'draft'},
    };
    final draft = SiteOrderRamDraft()..replace(body);
    (body['nested'] as Map)['name'] = 'changed';
    expect((draft.body!['nested'] as Map)['name'], 'draft');
    (draft.body!['nested'] as Map)['name'] = 'outside';
    expect((draft.body!['nested'] as Map)['name'], 'draft');
    draft.retire();
    expect(draft.body, isNull);
    expect(() => draft.replace(body), throwsStateError);
  });
  for (final state in [
    'not_observed',
    'prepared_review_required',
    'advanced',
    'changed',
  ]) {
    test('SDK $state preserves journal and never sends prepare', () async {
      await SiteOrderOutgoingJournal().begin(actor, company, entry());
      final wire = _Wire()..state = state;
      final (client, repo) = await _repository(wire);
      try {
        expect(await repo.inspectOutgoing(entry()), state);
        expect((await repo.pendingOutgoing(site)).length, 1);
        expect(wire.calls, 1);
        expect(wire.last!['action'], 'status');
      } finally {
        repo.dispose();
        await client.dispose();
      }
    });
  }
  test(
    'matching definitive retired receipt alone releases quarantine',
    () async {
      await SiteOrderOutgoingJournal().begin(actor, company, entry());
      final wire = _Wire()..state = 'retired';
      final (client, repo) = await _repository(wire);
      try {
        expect(await repo.retireOutgoing(entry(), confirmed: true), 'retired');
        expect(await repo.pendingOutgoing(site), isEmpty);
        expect(wire.last!['confirmed'], true);
      } finally {
        repo.dispose();
        await client.dispose();
      }
    },
  );
  for (final mode in [
    'wrong-company',
    'clear-without-retirement',
    'commit-ack-lost',
    'unconfirmed',
  ]) {
    test('SDK $mode cannot clear or repeat uncertain request', () async {
      await SiteOrderOutgoingJournal().begin(actor, company, entry());
      final wire = _Wire()
        ..wrongCompany = mode == 'wrong-company'
        ..forgedClear = mode == 'clear-without-retirement'
        ..status = mode == 'commit-ack-lost' ? 409 : 200;
      final (client, repo) = await _repository(wire);
      try {
        await expectLater(
          Future.sync(
            () =>
                repo.retireOutgoing(entry(), confirmed: mode != 'unconfirmed'),
          ),
          throwsA(anything),
        );
        expect(
          (await SiteOrderOutgoingJournal().read(actor, company, site)).length,
          1,
        );
        expect(wire.calls, mode == 'unconfirmed' ? 0 : 1);
      } finally {
        repo.dispose();
        await client.dispose();
      }
    });
  }
  testWidgets(
    'recovery offers inquiry and confirmed stop; unknown never becomes resend',
    (tester) async {
      final api = _RecoveryApi();
      await tester.pumpWidget(
        MaterialApp(
          home: SiteOrderOutgoingRecoveryPage(api: api, siteId: site),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('状態を照会'));
      await tester.pumpAndSettle();
      expect(api.reads, 1);
      expect(find.textContaining('結果はまだ確認できません'), findsOneWidget);
      expect(find.text('再送'), findsNothing);
      await tester.tap(find.text('準備を停止'));
      await tester.pumpAndSettle();
      expect(api.stops, 0);
      await tester.tap(find.text('戻る'));
      await tester.pumpAndSettle();
      expect(api.stops, 0);
      await tester.tap(find.text('準備を停止'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('停止を確認'));
      await tester.pumpAndSettle();
      expect(api.stops, 1);
      expect(find.text('閉じる'), findsOneWidget);
    },
  );
  testWidgets('scope retirement clears recovery identifiers and actions', (
    tester,
  ) async {
    final api = _RecoveryApi();
    await tester.pumpWidget(
      MaterialApp(
        home: SiteOrderOutgoingRecoveryPage(api: api, siteId: site),
      ),
    );
    await tester.pumpAndSettle();
    api.expired = true;
    api.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('状態を照会'), findsNothing);
    expect(find.textContaining(id(8)), findsNothing);
  });
  testWidgets(
    'failed initial journal read remains unknown, never empty-success',
    (tester) async {
      final api = _RecoveryApi()..failRead = true;
      await tester.pumpWidget(
        MaterialApp(
          home: SiteOrderOutgoingRecoveryPage(api: api, siteId: site),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('保存状態を確認できません'), findsOneWidget);
      expect(find.text('確認待ちの準備記録はありません。'), findsNothing);
    },
  );
}

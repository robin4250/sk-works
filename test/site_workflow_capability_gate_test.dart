import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/sites/site_order_workflow_repository.dart';
import 'package:sk_works/features/sites/site_order_outgoing_journal.dart';
import 'package:sk_works/features/sites/site_order_outgoing_consent.dart';

const actor = '10000000-0000-0000-0000-000000000001';
const company = '10000000-0000-0000-0000-000000000002';
const sid = '20000000-0000-0000-0000-000000000001';
const document = '30000000-0000-0000-0000-000000000001';

class Wire extends http.BaseClient {
  String actorId = actor, sessionId = sid, companyId = company;
  Object? capability;
  int capabilityStatus = 200, writes = 0, probes = 0;
  Completer<void>? hold, started;
  Map<String, dynamic> receipt() => {
    'contract_version': 1,
    'workflow_contract_version': 1,
    'actor_id': actor,
    'session_id': sid,
    'company_id': company,
    'role': 'manager',
    'master_enabled': true,
    'can_read': true,
    'can_create': true,
    'can_mutate': true,
  };
  Map<String, dynamic> session() {
    final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
    String part(Object o) =>
        base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
    return {
      'access_token':
          '${part({'alg': 'HS256'})}.${part({'sub': actorId, 'session_id': sessionId, 'role': 'authenticated', 'exp': expiry})}.synthetic',
      'refresh_token': 'synthetic-refresh',
      'expires_in': 3600,
      'expires_at': expiry,
      'token_type': 'bearer',
      'user': {
        'id': actorId,
        'aud': 'authenticated',
        'role': 'authenticated',
        'created_at': '2026-01-01T00:00:00Z',
      },
    };
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest r) async {
    Object? body;
    int status = 200;
    if (r.url.path == '/rest/v1/company_members') {
      body = [
        {'company_id': companyId, 'role': 'manager'},
      ];
    } else if (r.url.path == '/rest/v1/rpc/standalone_trade_document_access') {
      body = {
        'contract_version': 1,
        'actor_id': actor,
        'session_id': sid,
        'company_id': company,
        'role': 'manager',
        'master_enabled': true,
        'can_generate': true,
        'context_contract_version': 1,
      };
    } else if (r.url.path == '/rest/v1/rpc/site_order_workflow_capabilities') {
      probes++;
      if (started?.isCompleted == false) started!.complete();
      await hold?.future;
      body = capability;
      status = capabilityStatus;
      if (status != 200) {
        body = {'code': 'PGRST202', 'message': 'missing capability'};
      }
    } else {
      expect(r.url.path, '/functions/v1/site-order-workflow');
      writes++;
      body = {
        'result': {
          'package_id': document,
          'status': 'recipient_stored',
          'original_receipt_id': document,
        },
      };
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      status,
      headers: {'content-type': 'application/json'},
      request: r,
    );
  }
}

Future<(SupabaseClient, SiteOrderWorkflowRepository)> fixture(Wire w) async {
  final c = SupabaseClient(
    'https://synthetic.invalid',
    'synthetic-public',
    httpClient: w,
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  await c.auth.setInitialSession(jsonEncode(w.session()));
  await c.auth.recoverSession(jsonEncode(w.session()));
  return (c, SiteOrderWorkflowRepository(c));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'standalone ON receipt cannot substitute missing or malformed site capability',
    () async {
      final w = Wire();
      final (c, api) = await fixture(w);
      try {
        final valid = w.receipt();
        final bad = <Object?>[
          null,
          {},
          {...valid, 'unexpected': true},
          {...valid, 'workflow_contract_version': 2},
          {...valid, 'workflow_contract_version': 1.0},
          {...valid, 'contract_version': true},
          {...valid, 'can_read': false},
          {...valid, 'can_read': 1},
          {...valid, 'can_mutate': 1},
          {...valid, 'can_mutate': false},
          {...valid, 'can_create': 'true'},
          {...valid, 'actor_id': 'foreign'},
          {...valid, 'session_id': 'foreign'},
          {...valid, 'company_id': 'foreign'},
          {...valid, 'role': 'owner'},
          {...valid, 'master_enabled': false},
        ];
        for (final value in bad) {
          w.capability = value;
          expect(await api.canCreateOutgoing(), false);
          await expectLater(api.resume(document), throwsStateError);
          expect(w.writes, 0);
        }
        w.capabilityStatus = 404;
        expect(await api.canCreateOutgoing(), false);
        await expectLater(api.resume(document), throwsStateError);
        expect(w.writes, 0);
      } finally {
        api.dispose();
        await c.dispose();
      }
    },
  );
  test(
    'valid separate capability is re-read before every mutation and can be revoked',
    () async {
      final w = Wire();
      w.capability = w.receipt();
      final (c, api) = await fixture(w);
      try {
        expect(await api.canCreateOutgoing(), true);
        expect(w.probes, 1);
        await api.resume(document);
        expect(w.probes, 2);
        expect(w.writes, 1);
        w.capability = {...w.receipt(), 'can_mutate': false};
        await expectLater(api.resume(document), throwsStateError);
        expect(w.probes, 3);
        expect(w.writes, 1);
      } finally {
        api.dispose();
        await c.dispose();
      }
    },
  );
  SiteOrderPendingPrepare entry() => SiteOrderPendingPrepare(
    siteId: document,
    documentId: document,
    localId: '40000000-0000-0000-0000-000000000001',
    tradeId: document,
    requestId: '50000000-0000-0000-0000-000000000001',
    sessionId: sid,
  );
  test(
    'create denied despite mutate permission leaves no prepare journal or Edge request',
    () async {
      final w = Wire();
      w.capability = {...w.receipt(), 'can_create': false};
      final (c, api) = await fixture(w);
      try {
        expect(await api.canUseWorkflow(), true);
        expect(await api.canCreateOutgoing(), false);
        await expectLater(
          api.prepareUnsignedOutgoing(entry(), {
            'transaction_id': document,
            'issuer_company_id': company,
            'kind': 'order',
          }, 'a' * 64),
          throwsStateError,
        );
        expect(w.writes, 0);
        expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
      } finally {
        api.dispose();
        await c.dispose();
      }
    },
  );
  test(
    'known missing capability blocks all journal admission and site reads; old quarantine retained',
    () async {
      final w = Wire();
      w.capabilityStatus = 404;
      final (c, api) = await fixture(w);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('existing-quarantine', 'retain-exactly');
      final ref = SiteOrderConsentReference(
        prepare: entry(),
        previewId: '60000000-0000-0000-0000-000000000001',
        operationId: '70000000-0000-0000-0000-000000000001',
        decisionId: '80000000-0000-0000-0000-000000000001',
        bodyHash: 'a' * 64,
      );
      try {
        expect(await api.canUseWorkflow(), false);
        final review = {'package_id': document, 'preview_id': document};
        for (final action in <Future<Object?> Function()>[
          () => api.prepareUnsignedOutgoing(entry(), {
            'transaction_id': document,
            'issuer_company_id': company,
            'kind': 'order',
          }, 'a' * 64),
          () => api.confirmUnsignedOutgoing(ref, confirmed: true),
          () => api.registerOutgoingOriginal(
            ref,
            jobId: document,
            recipientCompanyId: document,
            confirmed: true,
          ),
          () => api.approve(review, sid),
          () => api.refuse(document, sid),
          () => api.recoverReply(review, sid),
          () => api.history(),
          () => api.detail(document),
          () => api.targets(document),
        ]) {
          await expectLater(action(), throwsStateError);
          expect(w.writes, 0);
          expect(prefs.getKeys(), {'existing-quarantine'});
          expect(prefs.getString('existing-quarantine'), 'retain-exactly');
        }
      } finally {
        api.dispose();
        await c.dispose();
      }
    },
  );
  for (final change in ['company', 'actor', 'session']) {
    test('pending valid receipt discarded after $change changes', () async {
      final w = Wire();
      w.capability = w.receipt();
      w.hold = Completer();
      w.started = Completer();
      final (c, api) = await fixture(w);
      try {
        final result = api.resume(document);
        final check = expectLater(result, throwsStateError);
        await w.started!.future;
        if (change == 'company') {
          w.companyId = '10000000-0000-0000-0000-000000000003';
        } else {
          if (change == 'actor') {
            w.actorId = '10000000-0000-0000-0000-000000000003';
          } else {
            w.sessionId = '20000000-0000-0000-0000-000000000003';
          }
          await c.auth.recoverSession(jsonEncode(w.session()));
        }
        w.hold!.complete();
        await check;
        expect(w.writes, 0);
        expect(api.invalidated, true);
      } finally {
        if (!w.hold!.isCompleted) w.hold!.complete();
        api.dispose();
        await c.dispose();
      }
    });
  }
}

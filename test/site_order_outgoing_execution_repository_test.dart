import 'site_workflow_capability_fixture.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sk_works/features/sites/site_order_outgoing_consent.dart';
import 'package:sk_works/features/sites/site_order_journal_serial.dart';
import 'package:sk_works/features/sites/site_order_outgoing_journal.dart';
import 'package:sk_works/features/sites/site_order_workflow_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _ExecutionWire extends http.BaseClient {
  _ExecutionWire(this.data, this.stage);
  final Map<String, dynamic> data;
  final String stage;
  int mutations = 0, statuses = 0, prepares = 0, consents = 0;
  String? lastStage;
  final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
  String token() {
    String part(Object x) =>
        base64Url.encode(utf8.encode(jsonEncode(x))).replaceAll('=', '');
    return '${part({'alg': 'HS256'})}.${part({'sub': data['actor'], 'session_id': data['session'], 'role': 'authenticated', 'exp': expiry})}.${part('synthetic-sdk-session')}';
  }

  Map<String, dynamic> get session => {
    'access_token': token(),
    'refresh_token': 'synthetic',
    'expires_in': 3600,
    'expires_at': expiry,
    'token_type': 'bearer',
    'user': {
      'id': data['actor'],
      'aud': 'authenticated',
      'role': 'authenticated',
      'created_at': '2026-01-01T00:00:00Z',
    },
  };
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path == '/rest/v1/rpc/site_order_workflow_capabilities') {
      return supportedSiteWorkflowCapability(request, actor: data['actor'], company: data['company'], session: data['session']);
    }
    Object body;
    int status = 200;
    if (request.url.path == '/rest/v1/company_members') {
      body = [
        {'company_id': data['company'], 'role': 'manager'},
      ];
    } else if (request.url.path ==
        '/rest/v1/rpc/standalone_trade_document_access') {
      body = {
        'contract_version': 1,
        'context_contract_version': 1,
        'actor_id': data['actor'],
        'company_id': data['company'],
        'session_id': data['session'],
        'role': 'manager',
        'master_enabled': true,
        'can_generate': true,
      };
    } else {
      expect(request.url.path, '/functions/v1/site-order-workflow/outgoing');
      final command = jsonDecode((request as http.Request).body) as Map;
      for (final e in (data['identity'] as Map).entries) {
        if (![
              'prepare',
              'status',
              'preview_unsigned',
            ].contains(command['action']) ||
            !['preview_id', 'decision_id'].contains(e.key)) {
          expect(command[e.key], e.value);
        }
      }
      if ([
        'prepare',
        'status',
        'preview_unsigned',
        'confirm_unsigned',
        'decision_status',
      ].contains(command['action'])) {
        final consent = data['consent'] as Map;
        if (command['action'] == 'prepare') {
          prepares++;
          expect(command['body'], consent['input_body']);
          expect(
            command['connection_fingerprint'],
            consent['connection_fingerprint'],
          );
          final prefs = await SharedPreferences.getInstance();
          expect(
            prefs
                .getKeys()
                .where((k) => k.startsWith('sko.site_order.outgoing.v1.'))
                .length,
            1,
          );
          status = 409;
          body = {'error': 'result_unknown'};
        } else if (command['action'] == 'status') {
          body = {'result': consent['prepared']};
        } else if (command['action'] == 'preview_unsigned') {
          body = {'result': consent['preview']};
        } else if (command['action'] == 'confirm_unsigned') {
          consents++;
          expect(command['confirmed'], true);
          final prefs = await SharedPreferences.getInstance();
          expect(
            prefs
                .getKeys()
                .where((k) => k.startsWith('sko.site_order.consent.v1.'))
                .length,
            1,
          );
          status = 409;
          body = {'error': 'result_unknown'};
        } else {
          body = {'result': consent['result']};
        }
      } else if (command['action'] == 'original_bytes') {
        final bytes = base64Decode(data['synthetic_pdf_base64'] as String);
        return http.StreamedResponse(
          Stream.value(bytes),
          200,
          headers: {'content-type': 'application/octet-stream'},
          request: request,
        );
      } else if (command['action'] == 'original_review') {
        body = {'result': data['persisted_review']};
      } else if (command['action'] == 'original_status') {
        statuses++;
        body = {
          'result':
              data[mutations == 0
                  ? 'no_original'
                  : lastStage == 'original'
                  ? 'original'
                  : 'shared'],
        };
      } else {
        if (stage == 'both') {
          expect([
            'register_outgoing_original',
            'share_confirmed',
          ], contains(command['action']));
        } else {
          expect(
            command['action'],
            stage == 'original'
                ? 'register_outgoing_original'
                : 'share_confirmed',
          );
        }
        lastStage = command['action'] == 'register_outgoing_original'
            ? 'original'
            : 'share';
        if (lastStage == 'share') expect(command['confirmed'], true);
        mutations++;
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs
              .getKeys()
              .where((k) => k.startsWith('sko.site_order.execution.v1.'))
              .length,
          stage == 'both' ? mutations : 1,
        );
        // Native fixture already committed this write and discarded its ACK.
        status = 409;
        body = {'error': 'result_unknown'};
      }
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      status,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final path = Platform.environment['SKO_EXECUTION_RECEIPT_PATH'];
  final consentPath = Platform.environment['SKO_CONSENT_RECEIPT_PATH'];
  test('Native full purpose crosses SDK prepare consent execution and append-only archival', () async {
    final data = Map<String, dynamic>.from(
      jsonDecode(File(path!).readAsStringSync()) as Map,
    );
    data['consent'] = jsonDecode(File(consentPath!).readAsStringSync());
    final consent = data['consent'] as Map;
    final identity = Map<String, dynamic>.from(data['identity'] as Map)
      ..remove('preview_id')
      ..remove('decision_id');
    final prepare = SiteOrderPendingPrepare.fromJson({
      ...identity,
      'session_id': data['session'],
    });
    final wire = _ExecutionWire(data, 'both');
    final client = SupabaseClient(
      'https://execution-sdk.invalid',
      'synthetic-public',
      httpClient: wire,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    await client.auth.setInitialSession(jsonEncode(wire.session));
    final repository = SiteOrderWorkflowRepository(client);
    try {
      await expectLater(
        repository.prepareUnsignedOutgoing(
          prepare,
          Map<String, dynamic>.from(consent['input_body'] as Map),
          consent['connection_fingerprint'] as String,
        ),
        throwsA(isA<SiteOrderResultUnknown>()),
      );
      expect(
        await repository.inspectUnsignedForReview(prepare),
        'prepared_review_required',
      );
      final preview = await repository.previewUnsignedOutgoing(prepare);
      final reference = SiteOrderConsentReference.fromPreview(
        prepare,
        preview,
        (data['identity'] as Map)['decision_id'],
      );
      await expectLater(
        repository.confirmUnsignedOutgoing(reference, confirmed: true),
        throwsA(isA<SiteOrderResultUnknown>()),
      );
      expect(
        (await repository.inspectOutgoingConsent(reference)).jobId,
        data['job_id'],
      );
      await expectLater(
        repository.registerOutgoingOriginal(
          reference,
          jobId: data['job_id'],
          recipientCompanyId: data['recipient_company_id'],
          confirmed: true,
        ),
        throwsA(isA<SiteOrderResultUnknown>()),
      );
      expect(
        (await repository.inspectOutgoingExecution(
          reference,
          jobId: data['job_id'],
          recipientCompanyId: data['recipient_company_id'],
        )).originalSaved,
        true,
      );
      await expectLater(
        repository.shareOutgoingOriginal(
          reference,
          jobId: data['job_id'],
          recipientCompanyId: data['recipient_company_id'],
          confirmed: true,
        ),
        throwsA(isA<SiteOrderResultUnknown>()),
      );
      final p = await SharedPreferences.getInstance();
      final before = {for (final key in p.getKeys()) key: p.getString(key)};
      final recorded = await repository.recordOutgoingDelivery(
        reference,
        jobId: data['job_id'],
        recipientCompanyId: data['recipient_company_id'],
      );
      expect(recorded.toJson()['recipient_approval_state'], 'not_checked');
      for (final e in before.entries) {
        expect(p.getString(e.key), e.value);
      }
      expect(
        p.containsKey(
          siteOrderDeliveryMarkerKey(
            data['actor'],
            data['company'],
            prepare.siteId,
            prepare.requestId,
          ),
        ),
        true,
      );
      expect(await repository.pendingOutgoing(prepare.siteId), isEmpty);
      expect(await repository.pendingOutgoingConsents(prepare.siteId), isEmpty);
      expect(
        (await repository.recordedOutgoing(prepare.siteId)).single.packageId,
        recorded.packageId,
      );
      await expectLater(
        repository.shareOutgoingOriginal(
          reference,
          jobId: data['job_id'],
          recipientCompanyId: data['recipient_company_id'],
          confirmed: true,
        ),
        throwsStateError,
      );
      final recovered = await repository.recordOutgoingDelivery(
        reference,
        jobId: data['job_id'],
        recipientCompanyId: data['recipient_company_id'],
      );
      expect(recovered.toJson(), recorded.toJson());
      expect(wire.prepares, 1);
      expect(wire.consents, 1);
      expect(wire.mutations, 2);
    } finally {
      repository.dispose();
      await client.dispose();
    }
  }, skip: path == null || consentPath == null);
  for (final stage in ['original', 'share']) {
    test(
      'Native $stage ACK loss crosses actual SDK quarantine and exact status',
      () async {
        final data = Map<String, dynamic>.from(
          jsonDecode(File(path!).readAsStringSync()) as Map,
        );
        expect(data['synthetic_auth'], true);
        expect(data['real_GoTrue'], false);
        expect(data['production_changed'], false);
        final identity = Map<String, dynamic>.from(data['identity'] as Map);
        final prepare = Map<String, dynamic>.from(identity)
          ..remove('preview_id')
          ..remove('decision_id');
        prepare['session_id'] = data['session'];
        final reference = SiteOrderConsentReference(
          prepare: SiteOrderPendingPrepare.fromJson(prepare),
          previewId: identity['preview_id'],
          decisionId: identity['decision_id'],
          operationId: data['operation_id'],
          bodyHash: data['body_hash'],
        );
        final wire = _ExecutionWire(data, stage);
        final client = SupabaseClient(
          'https://execution-sdk.invalid',
          'synthetic-public',
          httpClient: wire,
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        );
        await client.auth.setInitialSession(jsonEncode(wire.session));
        final repository = SiteOrderWorkflowRepository(client);
        Future<Object> execute() => stage == 'original'
            ? repository.registerOutgoingOriginal(
                reference,
                jobId: data['job_id'],
                recipientCompanyId: data['recipient_company_id'],
                confirmed: true,
              )
            : repository.shareOutgoingOriginal(
                reference,
                jobId: data['job_id'],
                recipientCompanyId: data['recipient_company_id'],
                confirmed: true,
              );
        try {
          await expectLater(execute(), throwsA(isA<SiteOrderResultUnknown>()));
          final observed = await repository.inspectOutgoingExecution(
            reference,
            jobId: data['job_id'],
            recipientCompanyId: data['recipient_company_id'],
          );
          final resolved = await repository.resolveOutgoingExecutionForReview(
            reference,
            jobId: data['job_id'],
          );
          expect(resolved.recipientCompanyId, data['recipient_company_id']);
          final review = await repository.reviewOutgoingOriginal(
            reference,
            jobId: data['job_id'],
            recipientCompanyId: data['recipient_company_id'],
          );
          final bytes = await repository.outgoingOriginalBytes(
            reference,
            review,
          );
          expect(bytes, base64Decode(data['synthetic_pdf_base64'] as String));
          expect(observed.originalSaved, true);
          expect(observed.recipientStored, stage == 'share');
          expect(observed.journalClearable, false);
          expect(observed.retryAutomatically, false);
          await expectLater(execute(), throwsStateError);
          expect(wire.mutations, 1);
          expect(wire.statuses, 2);
        } finally {
          repository.dispose();
          await client.dispose();
        }
      },
      skip: path == null,
    );
  }
}

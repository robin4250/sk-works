import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sk_works/features/sites/site_order_outgoing_consent.dart';
import 'package:sk_works/features/sites/site_order_outgoing_journal.dart';
import 'package:sk_works/features/sites/site_order_workflow_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _ExecutionWire extends http.BaseClient {
  _ExecutionWire(this.data, this.stage);
  final Map<String, dynamic> data;
  final String stage;
  int mutations = 0, statuses = 0;
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
        expect(command[e.key], e.value);
      }
      if (command['action'] == 'original_bytes') {
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
                  : stage == 'original'
                  ? 'original'
                  : 'shared'],
        };
      } else {
        expect(
          command['action'],
          stage == 'original'
              ? 'register_outgoing_original'
              : 'share_confirmed',
        );
        if (stage == 'share') expect(command['confirmed'], true);
        mutations++;
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs
              .getKeys()
              .where((k) => k.startsWith('sko.site_order.execution.v1.'))
              .length,
          1,
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
          expect(wire.statuses, 1);
        } finally {
          repository.dispose();
          await client.dispose();
        }
      },
      skip: path == null,
    );
  }
}

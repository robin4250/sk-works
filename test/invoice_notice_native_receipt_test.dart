import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sk_works/features/invoices/invoice_notice_recovery_controller.dart';
import 'package:sk_works/features/invoices/invoice_notice_ticket_controller.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('actual lost-COMMIT PostgreSQL stored scope is accepted by Dart and foreign receipt rejected', () async {
    final file = Platform.environment['SKO_NOTICE_CLIENT_RECEIPT_FIXTURE'];
    expect(file, isNotNull, reason: 'Native composition CI must generate this receipt first');
    final fixture = jsonDecode(await File(file!).readAsString()) as Map<String, dynamic>;
    final receipt = fixture['receipt'] as Map<String, dynamic>;
    final scope = receipt['scope'] as Map<String, dynamic>;
    final operation = InvoiceNoticeOperation(ticketId: scope['ticket_id'] as String,
      localDocumentId: scope['local_document_id'] as String,
      companyId: scope['company_id'] as String, revision: scope['revision'] as int,
      requestId: scope['request_id'] as String, expectedHash: scope['expected_hash'] as String,
      expectedPreview: fixture['expected_preview'] as Map<String, dynamic>);
    var submissions = 0, reads = 0;
    Object? response = receipt;
    final client = SupabaseClient('http://127.0.0.1:1', 'synthetic-fixture-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        expect(request.url.path, '/rest/v1/rpc/fixture_scoped_result');
        expect(jsonDecode(request.body), operation.parameters);
        reads++;
        return http.Response(jsonEncode(response), 200,
          headers: {'content-type': 'application/json'}, request: request);
      }));
    addTearDown(client.dispose);
    final recovery = InvoiceNoticeRecoveryController(
      actor: () => scope['actor_id'] as String, session: () => scope['session_id'] as String,
      openTicket: (id) async => {'notification_id': id,
        'invoice_id': operation.localDocumentId, 'ticket_id': operation.ticketId,
        'expires_at': DateTime.now().toUtc().add(const Duration(minutes: 1)).toIso8601String()},
      operationForTicket: (_) => operation,
      // The real command was already committed by the native fixture. Never
      // execute it again: simulate only its lost client response here.
      confirm: (_) async { submissions++; throw const SocketException('fixture lost response'); },
      readResult: (_) async => await client.rpc('fixture_scoped_result', params: operation.parameters));
    expect(await recovery.tickets.open(operation.ticketId, invoiceId: operation.localDocumentId), true);
    expect(await recovery.tickets.approve(), InvoiceNoticeApprovalResult.unconfirmed);
    // Each field is authoritative stored PostgreSQL data, not request echo.
    for (final key in scope.keys) {
      response = {...receipt, 'scope': {...scope, key: key == 'revision' ? -1 : 'foreign'}};
      expect(await recovery.reconcile(), false, reason: key);
    }
    response = {...receipt}..remove('scope');
    expect(await recovery.reconcile(), false);
    response = receipt;
    expect(await recovery.reconcile(), true);
    expect(recovery.state, InvoiceNoticeRecoveryState.recorded);
    expect(await recovery.tickets.open(operation.ticketId, invoiceId: operation.localDocumentId), false);
    expect(submissions, 1); expect(reads, scope.length + 2);
    recovery.invalidate();
    expect(await recovery.reconcile(), false);
  }, skip: Platform.environment['SKO_NOTICE_CLIENT_RECEIPT_FIXTURE'] == null &&
      Platform.environment['SKO_NOTICE_NATIVE_RECEIPT_REQUIRED'] != 'true'
      ? 'Requires the dedicated PostgreSQL receipt fixture' : false);
}

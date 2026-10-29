import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sk_works/features/invoices/invoice_notice_recovery_controller.dart';
import 'package:sk_works/features/invoices/invoice_notice_ticket_controller.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const id = '10000000-0000-0000-0000-000000000001';
final hash = List.filled(64, 'a').join();
Map<String, dynamic> recorded() => {'found': true, 'status': 'recorded',
  'scope': {...(operation().parameters..remove('expected_preview')),
    'actor_id': 'actor', 'session_id': 'sid'}, 'result': {
  'financial_approved': true, 'seal_consent_recorded': true}};

InvoiceNoticeOperation operation([Map<String, dynamic>? preview]) => InvoiceNoticeOperation(
  ticketId: id, localDocumentId: id, companyId: id, revision: 3,
  requestId: id, expectedHash: hash, expectedPreview: preview ?? {'amount': 110000, 'source_revision': 3});

void main() {
  late String? actor, sid;
  late int submissions, reads;
  late InvoiceNoticeRecoveryController recovery;
  Future<Object?> Function(InvoiceNoticeOperation) confirm = (_) async => null;
  Future<Object?> Function(InvoiceNoticeOperation) read = (_) async => recorded();
  Future<void> open() async => expect(await recovery.tickets.open(id, invoiceId: id), true);
  setUp(() {
    actor = 'actor'; sid = 'sid'; submissions = 0; reads = 0;
    confirm = (_) async => null; read = (_) async => recorded();
    recovery = InvoiceNoticeRecoveryController(actor: () => actor, session: () => sid,
      timeout: const Duration(milliseconds: 10),
      openTicket: (_) async => {'notification_id': id, 'invoice_id': id,
        'ticket_id': id, 'expires_at': DateTime.now().toUtc().add(const Duration(minutes: 1)).toIso8601String()},
      operationForTicket: (_) => operation(),
      confirm: (op) { submissions++; return confirm(op); },
      readResult: (op) { reads++; return read(op); });
  });

  test('successful command remains provisional until immutable read', () async {
    confirm = (_) async => true;
    await open();
    expect(await recovery.tickets.approve(), InvoiceNoticeApprovalResult.unconfirmed);
    expect(recovery.state, InvoiceNoticeRecoveryState.awaitingResult);
    expect(await recovery.reconcile(), true);
    expect(recovery.state, InvoiceNoticeRecoveryState.recorded);
    expect(await recovery.tickets.open(id, invoiceId: id), false);
    expect(await recovery.tickets.approve(), InvoiceNoticeApprovalResult.notSubmitted);
    expect(submissions, 1);
  });
  test('missing or failed read never releases operation for resend', () async {
    confirm = (_) async => throw StateError('response lost');
    await open(); await recovery.tickets.approve();
    read = (_) async => {'found': false};
    expect(await recovery.reconcile(), false);
    read = (_) async => throw StateError('offline');
    expect(await recovery.reconcile(), false);
    expect(await recovery.tickets.open(id, invoiceId: id), false);
    read = (_) async => recorded();
    expect(await recovery.reconcile(), true);
    expect(submissions, 1); expect(reads, 3);
  });
  test('preview and complete identity are detached from mutable caller data', () {
    final preview = <String, dynamic>{'items': [1, 2]};
    final op = operation(preview);
    (preview['items'] as List).add(3);
    (op.parameters['expected_preview']['items'] as List).clear();
    expect(op.parameters, {'ticket_id': id, 'local_document_id': id,
      'company_id': id, 'revision': 3, 'request_id': id, 'expected_hash': hash,
      'expected_preview': {'items': [1, 2]}});
    expect(() => InvoiceNoticeOperation(ticketId: id, localDocumentId: id,
      companyId: 'wrong', revision: 1, requestId: id, expectedHash: hash, expectedPreview: {'a': 1}), throwsArgumentError);
  });
  test('same actor with changed SID cannot query historical result', () async {
    await open(); await recovery.tickets.approve(); sid = 'other';
    expect(await recovery.reconcile(), false); expect(reads, 0);
    sid = 'sid'; expect(await recovery.reconcile(), false);
    expect(recovery.state, InvoiceNoticeRecoveryState.invalidated);
  });
  test('logout cancels delayed submit even if same actor SID return', () async {
    final pending = Completer<Object?>(); confirm = (_) => pending.future;
    await open(); final submitted = recovery.tickets.approve();
    recovery.invalidate(); actor = null; sid = null;
    actor = 'actor'; sid = 'sid'; pending.complete(true);
    expect(await submitted, InvoiceNoticeApprovalResult.unconfirmed);
    expect(await recovery.reconcile(), false); expect(reads, 0);
    expect(await recovery.tickets.open(id, invoiceId: id), false);
  });
  test('logout rejects delayed recorded read and concurrent read', () async {
    await open(); await recovery.tickets.approve();
    final pending = Completer<Object?>(); read = (_) => pending.future;
    final reading = recovery.reconcile();
    expect(await recovery.reconcile(), false);
    recovery.invalidate(); pending.complete(recorded());
    expect(await reading, false);
    expect(recovery.state, InvoiceNoticeRecoveryState.invalidated); expect(reads, 1);
  });
  test('malformed or partial recorded result cannot confirm', () async {
    await open(); await recovery.tickets.approve();
    for (final receipt in [true, {'found': true, 'status': 'recorded'},
      {'found': true, 'status': 'recorded', 'result': {'financial_approved': true}},
      {'found': true, 'status': 'pending', 'result': recorded()['result']}]) {
      read = (_) async => receipt;
      expect(await recovery.reconcile(), false);
    }
  });
  test('timed out submit and read never permit resend or apply late result', () async {
    final submit = Completer<Object?>(), lookup = Completer<Object?>();
    confirm = (_) => submit.future;
    await open();
    expect(await recovery.tickets.approve(), InvoiceNoticeApprovalResult.unconfirmed);
    read = (_) => lookup.future;
    expect(await recovery.reconcile(), false);
    lookup.complete(recorded()); submit.complete(true);
    await Future<void>.delayed(Duration.zero);
    expect(recovery.state, InvoiceNoticeRecoveryState.unavailable);
    expect(await recovery.tickets.open(id, invoiceId: id), false);
    read = (_) async => recorded();
    expect(await recovery.reconcile(), true); expect(submissions, 1);
  });
  test('legacy unbound and every foreign stored scope field fail closed', () async {
    await open(); await recovery.tickets.approve();
    final unbound = recorded()..remove('scope');
    read = (_) async => unbound;
    expect(await recovery.reconcile(), false);
    final scope = recorded()['scope'] as Map;
    for (final key in scope.keys) {
      final foreign = recorded();
      (foreign['scope'] as Map)[key] = key == 'revision' ? 4 : 'foreign';
      read = (_) async => foreign;
      expect(await recovery.reconcile(), false, reason: key.toString());
      expect(recovery.state, InvoiceNoticeRecoveryState.unavailable);
    }
    read = (_) async => recorded();
    expect(await recovery.reconcile(), true); expect(submissions, 1);
  });
  test('real Supabase SDK HTTP error reconciles exact snapshot without RPC resend', () async {
    final calls = <String>[]; final bodies = <Map<String, dynamic>>[];
    final client = SupabaseClient('http://127.0.0.1:1', 'synthetic-anon',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        calls.add(request.url.path); bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        if (calls.length == 1) { throw http.ClientException('fixture response lost'); }
        return http.Response(jsonEncode(recorded()), 200, headers: {'content-type': 'application/json'}, request: request);
      }));
    addTearDown(client.dispose);
    InvoiceNoticeOperation? submitted;
    recovery = InvoiceNoticeRecoveryController(actor: () => actor, session: () => sid,
      openTicket: (_) async => {'notification_id': id, 'invoice_id': id, 'ticket_id': id,
        'expires_at': DateTime.now().toUtc().add(const Duration(minutes: 1)).toIso8601String()},
      operationForTicket: (_) => operation(),
      // Synthetic fixture names only: no invented production/public contract.
      confirm: (op) { submitted = op; return client.rpc('fixture_confirm', params: op.parameters); },
      readResult: (op) { expect(identical(op, submitted), true);
        return client.rpc('fixture_read_result', params: op.parameters); });
    await open(); expect(await recovery.tickets.approve(), InvoiceNoticeApprovalResult.unconfirmed);
    expect(await recovery.reconcile(), true);
    expect(await recovery.tickets.open(id, invoiceId: id), false);
    expect(calls, ['/rest/v1/rpc/fixture_confirm', '/rest/v1/rpc/fixture_read_result']);
    expect(bodies[1], bodies[0]);
  });
}

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sk_works/features/invoices/invoice_notice_approval_panel.dart';
import 'package:sk_works/features/invoices/invoice_notice_recovery_controller.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const id = '10000000-0000-0000-0000-000000000001';
const revision = '2026-10-29T00:00:00Z';
final hash = List.filled(64, 'a').join();

void main() {
  late SupabaseClient client;
  late InvoiceNoticeRecoveryController recovery;
  late InvoiceNoticeRecoveryController Function() createRecovery;
  var sid = id, sent = 0, reads = 0, legacyReads = 0;
  Object? response;
  Future<Object?> Function()? delayed;
  Future<void> login() async { await client.auth.signInWithPassword(email: 'fixture@example.test', password: 'fixture'); }
  setUp(() async {
    sid = id; sent = 0; reads = 0; legacyReads = 0; delayed = null;
    client = SupabaseClient('http://127.0.0.1:1', 'synthetic-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        Object result = {};
        if (request.url.path == '/auth/v1/token') {
          String encode(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
          final token = '${encode({'alg': 'HS256'})}.${encode({'sub': id, 'session_id': sid,
            'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.c3ludGhldGlj';
          result = {'access_token': token, 'refresh_token': 'fixture-refresh', 'token_type': 'bearer', 'expires_in': 3600,
            'user': {'id': id, 'aud': 'authenticated', 'role': 'authenticated', 'email': 'fixture@example.test',
              'app_metadata': {}, 'user_metadata': {}, 'created_at': '2026-01-01T00:00:00Z'}};
        }
        return http.Response(jsonEncode(result), 200, request: request, headers: {'content-type': 'application/json'});
      }));
    await login();
    final operation = InvoiceNoticeOperation(ticketId: id, localDocumentId: id, companyId: id,
      revision: 1, requestId: id, expectedHash: hash, expectedPreview: {'amount': 1});
    response = {'found': true, 'status': 'recorded', 'scope': {
      ...(operation.parameters..remove('expected_preview')), 'actor_id': id, 'session_id': id},
      'result': {'financial_approved': true, 'seal_consent_recorded': true}};
    createRecovery = () => InvoiceNoticeRecoveryController(authClient: client,
      actor: () => client.auth.currentUser?.id, session: () => client.auth.currentSession == null ? null : sid,
      openTicket: (_) async => {'notification_id': id, 'invoice_id': id, 'ticket_id': id,
        'status': 'ready', 'source_revision': revision,
        'expires_at': DateTime.now().toUtc().add(const Duration(minutes: 1)).toIso8601String()},
      operationForTicket: (_) => operation,
      confirm: (_) async { sent++; throw StateError('response lost'); },
      readResult: (_) { reads++; return delayed?.call() ?? Future.value(response); });
    recovery = createRecovery();
  });
  tearDown(() async { recovery.dispose(); await client.dispose(); });
  Widget panel() => MaterialApp(home: Scaffold(body: InvoiceNoticeApprovalPanel(
    controller: null, recoveryController: recovery, notificationId: id, invoiceId: id,
    revision: revision, isApprover: true, confirmSavedApproval: () async { legacyReads++; return true; })));

  test('immediate fresh same-SID login after constructor is never mistaken for replay', () async {
    recovery.dispose();
    recovery = createRecovery();
    // No delay/pump between subscription and the next real SDK login.
    await login();
    await Future<void>.delayed(Duration.zero);
    expect(recovery.state, InvoiceNoticeRecoveryState.invalidated);
    expect(await recovery.tickets.open(id, invoiceId: id), false);
    expect(sent, 0); expect(reads, 0);
  });
  test('real SDK logout history terminally invalidates even same identity returns', () async {
    await recovery.tickets.open(id, invoiceId: id);
    await recovery.tickets.approve();
    await client.auth.signOut(); await login();
    await Future<void>.delayed(Duration.zero);
    expect(recovery.state, InvoiceNoticeRecoveryState.invalidated);
    expect(await recovery.reconcile(), false); expect(reads, 0); expect(sent, 1);
  });
  test('real SDK same-SID refresh retains operation, new signedIn never does', () async {
    await recovery.tickets.open(id, invoiceId: id); await recovery.tickets.approve();
    await client.auth.refreshSession(); await Future<void>.delayed(Duration.zero);
    expect(await recovery.reconcile(), true);
    await login(); await Future<void>.delayed(Duration.zero);
    expect(recovery.state, InvoiceNoticeRecoveryState.invalidated);
  });
  test('same actor different SID invalidates using real SDK event history', () async {
    await recovery.tickets.open(id, invoiceId: id); await recovery.tickets.approve();
    sid = '10000000-0000-0000-0000-000000000002'; await login();
    await Future<void>.delayed(Duration.zero);
    expect(await recovery.reconcile(), false); expect(reads, 0);
  });
  testWidgets('existing panel reconciles ambiguous submit through scoped reader only', (tester) async {
    await tester.pumpWidget(panel()); await tester.pumpAndSettle();
    await tester.tap(find.text('承認する')); await tester.pumpAndSettle();
    expect(sent, 1); expect(reads, 1); expect(legacyReads, 0);
    expect(find.textContaining('再送せず'), findsNothing);
    expect(find.text('承認する'), findsNothing);
  });
  testWidgets('missing receipt permits read-only retry without reopen or resend', (tester) async {
    final saved = response; response = {'found': false};
    await tester.pumpWidget(panel()); await tester.pumpAndSettle();
    await tester.tap(find.text('承認する')); await tester.pumpAndSettle();
    expect(find.text('保存済みの承認結果を確認'), findsOneWidget);
    response = saved;
    await tester.tap(find.text('保存済みの承認結果を確認')); await tester.pumpAndSettle();
    expect(sent, 1); expect(reads, 2); expect(legacyReads, 0);
    expect(find.text('承認する'), findsNothing); expect(find.textContaining('再送せず'), findsNothing);
  });
  testWidgets('logout during pending read rejects late receipt and removes retry', (tester) async {
    final pending = Completer<Object?>(); delayed = () => pending.future;
    await tester.pumpWidget(panel()); await tester.pumpAndSettle();
    await tester.tap(find.text('承認する')); await tester.pump();
    await client.auth.signOut(); await login(); await tester.pump();
    pending.complete(response); await tester.pumpAndSettle();
    expect(recovery.state, InvoiceNoticeRecoveryState.invalidated);
    expect(find.text('保存済みの承認結果を確認'), findsNothing);
    expect(find.text('承認する'), findsNothing); expect(sent, 1); expect(legacyReads, 0);
  });
  testWidgets('background invalidates full recovery not only ticket', (tester) async {
    response = {'found': false};
    await tester.pumpWidget(panel()); await tester.pumpAndSettle();
    await tester.tap(find.text('承認する')); await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused); await tester.pump();
    expect(recovery.state, InvoiceNoticeRecoveryState.invalidated);
    // Paused apps do not produce frames. Verify the terminal model while
    // paused, then its rendered state on the first frame after resume.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('保存済みの承認結果を確認'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

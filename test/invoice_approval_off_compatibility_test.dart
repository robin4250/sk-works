import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/invoices/invoice_approval_entry_actions.dart';
import 'package:sk_works/features/invoices/invoice_notice_ticket_controller.dart';

void main() {
  const invoice = '00000000-0000-0000-0000-000000000001';
  const notice = '00000000-0000-0000-0000-000000000002';
  const ticket = '00000000-0000-0000-0000-000000000003';
  const revision = '2026-10-27T00:00:00Z';
  late int legacy, opens, submits;
  setUp(() { legacy = 0; opens = 0; submits = 0; });
  InvoiceNoticeTicketController controller({bool readFails = false, bool submitFails = false}) =>
      InvoiceNoticeTicketController(actor: () => 'actor', session: () => 'session',
        openTicket: (_) async {
          opens++;
          if (readFails) { throw StateError('fixture endpoint unavailable'); }
          return {'notification_id': notice, 'invoice_id': invoice, 'ticket_id': ticket,
            'expires_at': DateTime.now().toUtc().add(const Duration(minutes: 5)).toIso8601String(),
            'status': 'ready', 'source_revision': revision};
        }, submitApproval: (_) async {
          submits++;
          if (submitFails) { throw StateError('fixture unknown result'); }
          return true;
        });
  Widget page({bool notificationOnly = invoiceNoticeApprovalReleased,
    bool fromNotification = false, bool canApprove = true, bool busy = false,
    InvoiceNoticeTicketController? candidate}) => MaterialApp(home: Scaffold(
      body: InvoiceApprovalEntryActions(notificationOnly: notificationOnly,
        canApprove: canApprove, isPendingApprover: true,
        fromNotification: fromNotification, busy: busy,
        onLegacyApprove: () { legacy++; }, controller: candidate,
        notificationId: notice, invoiceId: invoice, revision: revision,
        confirmSavedApproval: () async => true)));

  test('production rollout is fixed OFF and exact main approval protections remain', () {
    expect(invoiceNoticeApprovalReleased, isFalse);
    final source = File('lib/features/invoices/invoice_pdf_service.dart').readAsStringSync();
    final start = source.indexOf('  Future<void> _approve() async {');
    expect(start, greaterThanOrEqualTo(0));
    final end = source.indexOf('  Future<void> _openAcceptanceEditor() async {', start);
    expect(end, greaterThan(start));
    // Exact method from canonical main 7355d28f: actor/permission/surname checks,
    // existing confirmation flow and saved-server-result reread are preserved.
    expect(sha256.convert(utf8.encode(source.substring(start, end))).toString(),
      'ee97cf5da13fbad5dba45d1826dd7c096c4cc35eed23bca1378b97f8a8682c3d');
    expect(source, contains('notificationOnly: invoiceNoticeApprovalReleased'));
    expect(source, contains('onLegacyApprove: invoiceNoticeApprovalReleased ? null : _approve'));
    expect(source, contains('_noticeController = invoiceNoticeApprovalReleased && SupabaseBackend.isInitialized'));
    expect(source, contains('enabled: invoiceNoticeApprovalReleased'));
  });
  for (final fromNotice in [false, true]) {
    testWidgets('OFF preserves legacy action and does not open candidate RPC, notification=$fromNotice', (tester) async {
      await tester.pumpWidget(page(fromNotification: fromNotice, candidate: controller()));
      await tester.pumpAndSettle();
      expect(find.text('承認'), findsOneWidget);
      expect(find.text('承認する'), findsNothing);
      expect(find.text('承認は通知から請求書を開いて行います。'), findsNothing);
      expect(opens, 0); expect(submits, 0);
      await tester.tap(find.text('承認')); await tester.pump();
      expect(legacy, 1); expect(opens, 0); expect(submits, 0);
    });
  }
  testWidgets('OFF keeps existing permission and busy button restrictions', (tester) async {
    await tester.pumpWidget(page(canApprove: false, candidate: controller()));
    expect(find.text('承認'), findsNothing);
    await tester.pumpWidget(page(busy: true, candidate: controller()));
    expect(find.text('承認中…'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    expect(legacy, 0); expect(opens, 0); expect(submits, 0);
  });
  testWidgets('ON missing controller never falls back to legacy approval', (tester) async {
    await tester.pumpWidget(page(notificationOnly: true, fromNotification: true));
    await tester.pumpAndSettle();
    expect(find.text('承認'), findsNothing); expect(find.text('承認する'), findsNothing);
    expect(legacy, 0); expect(opens, 0); expect(submits, 0);
  });
  testWidgets('ON failed ticket read never falls back to legacy approval', (tester) async {
    await tester.pumpWidget(page(notificationOnly: true, fromNotification: true,
      candidate: controller(readFails: true)));
    await tester.pumpAndSettle();
    expect(find.text('承認'), findsNothing); expect(find.text('承認する'), findsNothing);
    expect(legacy, 0); expect(opens, 1); expect(submits, 0);
  });
  testWidgets('ON uncertain candidate approval cannot invoke legacy fallback', (tester) async {
    await tester.pumpWidget(page(notificationOnly: true, fromNotification: true,
      candidate: controller(submitFails: true)));
    await tester.pumpAndSettle();
    expect(find.text('承認'), findsNothing);
    await tester.tap(find.text('承認する')); await tester.pumpAndSettle();
    expect(find.text('承認'), findsNothing); expect(find.text('承認する'), findsNothing);
    expect(find.textContaining('再送せず'), findsOneWidget);
    expect(legacy, 0); expect(opens, 1); expect(submits, 1);
  });
  testWidgets('ON normal entry only explains notification requirement without RPC', (tester) async {
    await tester.pumpWidget(page(notificationOnly: true, candidate: controller()));
    await tester.pumpAndSettle();
    expect(find.text('承認は通知から請求書を開いて行います。'), findsOneWidget);
    expect(find.text('承認'), findsNothing); expect(find.text('承認する'), findsNothing);
    expect(legacy, 0); expect(opens, 0); expect(submits, 0);
  });
}

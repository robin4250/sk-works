import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/invoices/invoice_notice_approval_panel.dart';
import 'package:sk_works/features/invoices/invoice_notice_ticket_controller.dart';

void main() {
  const invoice = '00000000-0000-0000-0000-000000000001';
  const notice = '00000000-0000-0000-0000-000000000002';
  const ticket = '00000000-0000-0000-0000-000000000003';
  const revision = '2026-10-27T00:00:00Z';
  Widget page(InvoiceNoticeTicketController? controller, Future<bool> Function() confirm) =>
    MaterialApp(home: Scaffold(body: InvoiceNoticeApprovalPanel(
      controller: controller, notificationId: notice, invoiceId: invoice,
      revision: revision, isApprover: true, confirmSavedApproval: confirm)));
  testWidgets('OFF panel makes no approval available', (tester) async {
    await tester.pumpWidget(page(null, () async => true));
    expect(find.text('承認する'), findsNothing);
    expect(find.text('再読み込み'), findsNothing);
  });
  testWidgets('revision proof is mandatory before approval can be dispatched', (tester) async {
    var sent = 0;
    final controller = InvoiceNoticeTicketController(actor: () => 'actor', session: () => 'session',
      openTicket: (_) async => {'notification_id': notice, 'invoice_id': invoice,
        'ticket_id': ticket, 'expires_at': DateTime.now().toUtc().add(const Duration(minutes: 5)).toIso8601String()},
      submitApproval: (_) async { sent++; return true; });
    await tester.pumpWidget(page(controller, () async => true));
    await tester.pumpAndSettle();
    expect(find.text('承認する'), findsNothing);
    expect(sent, 0);
  });
  testWidgets('saved approval must be reread and uncertain results cannot be resent', (tester) async {
    var sent = 0, reads = 0;
    final controller = InvoiceNoticeTicketController(actor: () => 'actor', session: () => 'session',
      openTicket: (_) async => {'notification_id': notice, 'invoice_id': invoice,
        'ticket_id': ticket, 'expires_at': DateTime.now().toUtc().add(const Duration(minutes: 5)).toIso8601String(),
        'status': 'ready', 'source_revision': revision},
      submitApproval: (_) async { sent++; return true; });
    await tester.pumpWidget(page(controller, () async { reads++; return false; }));
    await tester.pumpAndSettle();
    await tester.tap(find.text('承認する'));
    await tester.pumpAndSettle();
    expect(sent, 1);
    expect(reads, 1);
    expect(find.text('承認する'), findsNothing);
    expect(find.text('再読み込み'), findsNothing);
    expect(find.textContaining('再送せず'), findsOneWidget);
  });
}

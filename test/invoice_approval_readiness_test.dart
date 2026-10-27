import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/invoices/invoice_approval_readiness.dart';

void main() {
  InvoiceApprovalReadiness from(String status, {String id = 'invoice', String rev = 'revision'}) =>
      InvoiceApprovalReadiness.fromServer({'status': status, 'invoice_id': id, 'source_revision': rev}, invoiceId: 'invoice', revision: 'revision');
  Widget page(InvoiceApprovalReadiness state, {bool approver = true, bool busy = false, VoidCallback? onApprove}) =>
      MaterialApp(home: Scaffold(body: InvoiceApprovalReadinessNotice(readiness: state, isApprover: approver, busy: busy, onApprove: onApprove, onReload: () {})));

  test('unknown, malformed, wrong invoice and stale revision fail closed', () {
    for (final state in [from('unknown'), from('ready', id: 'other'), from('ready', rev: 'old'), InvoiceApprovalReadiness.fromServer(null, invoiceId: 'invoice', revision: 'revision')]) {
      expect(state.state, InvoiceApprovalReadinessState.unavailable);
    }
  });
  testWidgets('every pending condition explains why approval is unavailable', (tester) async {
    for (final entry in {'period_open': '対象月が終わると承認できます。', 'checkout_pending': '対象となる勤務の退勤が必要です。', 'report_pending': '対象となる日報の確定が必要です。'}.entries) {
      await tester.pumpWidget(page(from(entry.key), onApprove: () => fail('must not approve')));
      expect(find.text(entry.value), findsOneWidget);
      expect(find.text('承認する'), findsNothing);
    }
  });
  testWidgets('only eligible assigned approver can use the button', (tester) async {
    var calls = 0;
    await tester.pumpWidget(page(from('ready'), onApprove: () => calls++));
    await tester.tap(find.text('承認する'));
    expect(calls, 1);
    await tester.pumpWidget(page(from('ready'), approver: false, onApprove: () => calls++));
    expect(find.text('承認する'), findsNothing);
    await tester.pumpWidget(page(from('ready'), busy: true, onApprove: () => calls++));
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    await tester.pumpWidget(page(from('already_approved'), onApprove: () => calls++));
    expect(find.text('承認済み'), findsOneWidget);
    expect(find.text('承認する'), findsNothing);
  });
}

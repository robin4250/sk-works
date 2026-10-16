import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/invoices/invoice_cloud_page.dart';

void main() {
  Future<void> open(WidgetTester tester, ValueChanged<bool> result) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
      builder: (context) => TextButton(
        onPressed: () async => result(
          await showInvoiceApprovalCancellationConfirmation(context),
        ),
        child: const Text('open'),
      ),
    ))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('cancel keeps the existing approval', (tester) async {
    bool? confirmed;
    await open(tester, (value) => confirmed = value);
    expect(find.textContaining('ご自身の承認印'), findsOneWidget);
    await tester.tap(find.text('戻る'));
    await tester.pumpAndSettle();
    expect(confirmed, isFalse);
  });

  testWidgets('explicit confirmation requests own approval cancellation',
      (tester) async {
    bool? confirmed;
    await open(tester, (value) => confirmed = value);
    await tester.tap(find.text('承認を解除'));
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
  });

  testWidgets('dismissal does not cancel approval', (tester) async {
    bool? confirmed;
    await open(tester, (value) => confirmed = value);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(confirmed, isFalse);
  });
}

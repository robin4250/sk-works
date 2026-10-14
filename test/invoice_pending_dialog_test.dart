import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/invoices/invoice_pending_dialog.dart';

void main() {
  for (final failed in [false, true]) {
    testWidgets('pending without review access offers reload, failed=$failed', (tester) async {
      InvoicePendingAction? result;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
        return TextButton(onPressed: () async {
          result = await showDialog<InvoicePendingAction>(
            context: context,
            builder: (_) => InvoicePendingDialog(
              english: false, routeSourcePending: false,
              canReviewQuantity: false, quantityCheckFailed: failed,
            ),
          );
        }, child: const Text('開く'));
      })));
      await tester.tap(find.text('開く'));
      await tester.pumpAndSettle();
      expect(find.text('請求数量を確認'), findsNothing);
      expect(find.textContaining(failed ? '取得できませんでした' : '再計算が請求書に反映'), findsOneWidget);
      await tester.tap(find.text('再読み込み'));
      await tester.pumpAndSettle();
      expect(result, InvoicePendingAction.reload);
    });
  }
  testWidgets('review action requires successfully discovered requests', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: InvoicePendingDialog(
      english: true, routeSourcePending: false,
      canReviewQuantity: true, quantityCheckFailed: false,
    )));
    expect(find.text('Review Quantity'), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home: InvoicePendingDialog(
      english: true, routeSourcePending: true,
      canReviewQuantity: true, quantityCheckFailed: false,
    )));
    expect(find.text('Review Quantity'), findsNothing);
  });
}

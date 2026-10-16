import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/expenses/expense_claim.dart';
import 'package:sk_works/features/expenses/expense_personal_page.dart';
import 'package:sk_works/features/expenses/expense_receipt_attachment.dart';
import 'package:sk_works/features/expenses/expense_submission_repository.dart';

class _Access implements ExpenseSubmissionAccess {
  @override
  String? actor = 'actor';
  ExpenseSubmission? draft;
  Completer<void>? response;
  bool fail = false;
  bool failRefresh = false;
  final sent = <ExpenseSubmission>[];
  @override
  Future<List<Map<String, dynamic>>> scopes() async => [{
    'company_id': 'company', 'worker_id': 'worker',
    'company_name': '申請先会社', 'worker_name': '本人',
  }];
  @override
  Future<ExpenseSubmission?> pending(String company, String worker) async => draft;
  @override
  Future<List<ExpenseClaim>> history(String company, String worker, DateTime month) async {
    if (failRefresh && sent.isNotEmpty) throw StateError('history unavailable');
    return [];
  }
  @override
  Future<void> submit(ExpenseSubmission input) async {
    sent.add(input);
    draft = input;
    if (response != null) await response!.future;
    if (fail) throw StateError('response lost');
    draft = null;
  }
}

Future<void> _open(WidgetTester tester, _Access access,
    {ExpenseReceiptAttachment? receipt}) async {
  await tester.binding.setSurfaceSize(const Size(650, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
    return Scaffold(body: TextButton(
      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ExpensePersonalPage(access: access,
          pickReceipt: (_) async => receipt),
      )),
      child: const Text('open'),
    ));
  })));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).at(0), '現場の養生テープ');
  await tester.enterText(find.byType(TextField).at(1), '1200');
}

void main() {
  testWidgets('success is shown only after save and double acknowledgment keeps page',
      (tester) async {
    final access = _Access()..response = Completer<void>();
    await _open(tester, access);
    await tester.tap(find.text('申請する'));
    await tester.pump();
    expect(find.text('経費の申請が完了しました'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(ExpensePersonalPage), findsOneWidget);
    expect(access.sent, hasLength(1));
    access.response!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('経費の申請が完了しました'), findsOneWidget);
    expect(find.textContaining('申請先会社への経費申請を登録しました'), findsOneWidget);
    final acknowledge = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '申請履歴を確認')).onPressed!;
    acknowledge();
    acknowledge();
    await tester.pumpAndSettle();
    expect(find.byType(ExpensePersonalPage), findsOneWidget);
    expect(access.sent, hasLength(1));
  });

  testWidgets('unknown save keeps fixed request and receipt for exact retry',
      (tester) async {
    final dir = Directory.systemTemp.createTempSync('expense-completion-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/receipt.png')..writeAsBytesSync([1, 2, 3]);
    final receipt = ExpenseReceiptAttachment(file.path, 'a' * 64, 3, 'image/png');
    final access = _Access()..fail = true;
    await _open(tester, access, receipt: receipt);
    await tester.tap(find.text('写真を撮る'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('申請する'), 300,
      scrollable: find.descendant(of: find.byType(ListView),
        matching: find.byType(Scrollable)).first);
    await tester.tap(find.text('申請する'));
    await tester.pumpAndSettle();
    expect(find.text('経費の申請が完了しました'), findsNothing);
    final original = access.sent.single;
    expect(original.description, '現場の養生テープ');
    expect(original.amount, 1200);
    expect(original.receipt, same(receipt));
    expect(file.existsSync(), isTrue);
    access.fail = false;
    await tester.tap(find.text('同じ申請を再確認'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(access.sent.last.encoded, original.encoded);
    expect(access.sent, hasLength(2));
    expect(find.text('経費の申請が完了しました'), findsOneWidget);
    expect(file.existsSync(), isTrue);
    await tester.tap(find.text('申請履歴を確認'));
    await tester.pumpAndSettle();
  });

  testWidgets('history refresh failure retains confirmed success and never resubmits',
      (tester) async {
    final access = _Access()..failRefresh = true;
    await _open(tester, access);
    await tester.tap(find.text('申請する'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('経費の申請が完了しました'), findsOneWidget);
    await tester.tap(find.text('申請履歴を確認'));
    await tester.pumpAndSettle();
    expect(find.textContaining('申請は登録済みですが'), findsOneWidget);
    expect(tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '申請する')).onPressed, isNull);
    access.failRefresh = false;
    await tester.ensureVisible(find.text('再読み込み'));
    await tester.tap(find.text('再読み込み'));
    await tester.pumpAndSettle();
    expect(access.sent, hasLength(1));
    expect(find.textContaining('申請は登録済みですが'), findsNothing);
  });
}

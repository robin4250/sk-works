import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/expenses/expense_claim.dart';
import 'package:sk_works/features/expenses/expense_personal_page.dart';
import 'package:sk_works/features/expenses/expense_receipt_attachment.dart';
import 'package:sk_works/features/expenses/expense_submission_repository.dart';

class _Access implements ExpenseSubmissionAccess {
  @override String? actor = 'actor';
  final sent = <ExpenseSubmission>[];
  @override Future<List<Map<String,dynamic>>> scopes() async => [{'company_id':'company','company_name':'会社','worker_id':'worker','worker_name':'本人'}];
  @override Future<List<ExpenseClaim>> history(String c,String w,DateTime m) async => [];
  @override Future<ExpenseSubmission?> pending(String c,String w) async => null;
  @override Future<void> submit(ExpenseSubmission value) async { sent.add(value); }
}

Future<ExpenseReceiptAttachment> _photo(WidgetTester tester) async {
  final value = await tester.runAsync(() async {
    final directory = await Directory.systemTemp.createTemp('expense-ocr-');
    final bytes = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a6V8AAAAASUVORK5CYII=');
    final file = await File('${directory.path}/receipt.png').writeAsBytes(bytes);
    return (directory, ExpenseReceiptAttachment(file.path,sha256.convert(bytes).toString(),bytes.length,'image/png'));
  });
  addTearDown(() => tester.runAsync(() async { await value!.$1.delete(recursive:true); }));
  return value!.$2;
}

Future<void> _open(WidgetTester tester,_Access access,ExpenseReceiptAttachment photo,
    Future<String> Function(String) recognize) async {
  await tester.binding.setSurfaceSize(const Size(650,1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(home:ExpensePersonalPage(access:access,
    pickReceipt:(_) async => photo,recognizeReceiptText:recognize)));
  await tester.pumpAndSettle();
}

Finder get _amount => find.widgetWithText(TextField,'金額（円）');
Future<void> _capture(WidgetTester tester) async {
  await tester.ensureVisible(find.text('写真を撮る'));
  await tester.tap(find.text('写真を撮る'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('photo suggests a total but never submits until explicit application', (tester) async {
    final photo=await _photo(tester), access=_Access();
    await _open(tester,access,photo,(_) async => '合計 ¥1,234\nお預り 2,000円\nお釣り 766円');
    await _capture(tester);
    expect(tester.widget<TextField>(_amount).controller!.text,'1234');
    expect(find.textContaining('税込合計と金額を確認'),findsOneWidget);
    expect(access.sent,isEmpty);
    await tester.enterText(find.widgetWithText(TextField,'内容'),'現場の養生テープ');
    await tester.ensureVisible(find.text('申請する'));
    await tester.tap(find.text('申請する'));await tester.pump();
    expect(access.sent.single.amount,1234);expect(access.sent.single.receipt,same(photo));
    await tester.pump(const Duration(milliseconds:400));
    expect(find.text('経費の申請が完了しました'),findsOneWidget);
    await tester.tap(find.text('申請履歴を確認'));
    await tester.pumpAndSettle();
  });
  testWidgets('late result cannot overwrite a manually edited amount', (tester) async {
    final photo=await _photo(tester), access=_Access(), result=Completer<String>();
    await _open(tester,access,photo,(_) => result.future);
    await _capture(tester);
    await tester.enterText(_amount,'987');
    result.complete('合計 1234円');await tester.pumpAndSettle();
    expect(tester.widget<TextField>(_amount).controller!.text,'987');
    expect(find.textContaining('入力済みの金額は変更していません'),findsOneWidget);
    expect(access.sent,isEmpty);
  });
  testWidgets('existing amount is preserved and a candidate needs an explicit tap', (tester) async {
    final photo=await _photo(tester), access=_Access();
    await _open(tester,access,photo,(_) async => '合計 1234円');
    await tester.enterText(_amount,'500');await _capture(tester);
    expect(tester.widget<TextField>(_amount).controller!.text,'500');
    await tester.ensureVisible(find.text('合計 1234円'));await tester.tap(find.text('合計 1234円'));
    await tester.pump();expect(tester.widget<TextField>(_amount).controller!.text,'1234');
    expect(access.sent,isEmpty);
  });
  testWidgets('ambiguous totals and failed OCR preserve manual entry and never fill zero', (tester) async {
    final photo=await _photo(tester), access=_Access();var count=0;
    await _open(tester,access,photo,(_) async { if(count++==0)return '合計 1000円\n領収金額 900円';throw StateError('native failure'); });
    await _capture(tester);expect(tester.widget<TextField>(_amount).controller!.text,isEmpty);
    expect(find.text('合計 1000円'),findsOneWidget);expect(find.text('領収金額 900円'),findsOneWidget);
    await _capture(tester);expect(tester.widget<TextField>(_amount).controller!.text,isEmpty);
    expect(find.textContaining('写真は保持しています'),findsOneWidget);
    expect(find.text('申請前の領収書プレビュー'),findsOneWidget);expect(access.sent,isEmpty);
  });
  testWidgets('removing a photo retires its delayed OCR result', (tester) async {
    final photo=await _photo(tester), access=_Access(), result=Completer<String>();
    await _open(tester,access,photo,(_) => result.future);await _capture(tester);
    await tester.ensureVisible(find.text('写真を外す'));await tester.tap(find.text('写真を外す'));await tester.pump();
    result.complete('合計 1234円');await tester.pumpAndSettle();
    expect(tester.widget<TextField>(_amount).controller!.text,isEmpty);
    expect(find.text('合計 1234円'),findsNothing);expect(access.sent,isEmpty);
  });
  testWidgets('changing actor rejects delayed OCR and never submits', (tester) async {
    final photo=await _photo(tester), access=_Access(), result=Completer<String>();
    await _open(tester,access,photo,(_) => result.future);await _capture(tester);
    access.actor='other';result.complete('合計 1234円');await tester.pumpAndSettle();
    expect(tester.widget<TextField>(_amount).controller!.text,isEmpty);expect(access.sent,isEmpty);
  });
  testWidgets('disposing the page rejects delayed OCR without a state update', (tester) async {
    final photo=await _photo(tester), access=_Access(), result=Completer<String>();
    await _open(tester,access,photo,(_) => result.future);await _capture(tester);
    await tester.pumpWidget(const MaterialApp(home:SizedBox()));
    result.complete('合計 1234円');await tester.pumpAndSettle();
    expect(access.sent,isEmpty);expect(tester.takeException(),isNull);
  });
}

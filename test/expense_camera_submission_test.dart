import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sk_works/features/expenses/expense_claim.dart';
import 'package:sk_works/features/expenses/expense_personal_page.dart';
import 'package:sk_works/features/expenses/expense_receipt_attachment.dart';
import 'package:sk_works/features/expenses/expense_submission_repository.dart';

class Access implements ExpenseSubmissionAccess {
  @override String? get actor => 'actor';
  ExpenseSubmission? draft;
  final submitted=<ExpenseSubmission>[];
  @override Future<List<Map<String,dynamic>>> scopes()async=>[{'company_id':'company','company_name':'会社','worker_id':'worker','worker_name':'本人'}];
  @override Future<List<ExpenseClaim>> history(String c,String w,DateTime m)async=>[];
  @override Future<ExpenseSubmission?> pending(String c,String w)async=>draft;
  @override Future<void> submit(ExpenseSubmission value)async{draft=value;submitted.add(value);throw StateError('upload failed');}
}
void main(){
 testWidgets('camera preview is local until submit and failed upload preserves the exact photo and command', (tester)async{
  final fixture = await tester.runAsync(() async {
    final directory = await Directory.systemTemp.createTemp('expense-camera-test-');
    final bytes = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a6V8AAAAASUVORK5CYII=');
    final file = await File('${directory.path}/receipt.png').writeAsBytes(bytes);
    final photo = ExpenseReceiptAttachment(file.path, sha256.convert(bytes).toString(), bytes.length, 'image/png');
    expect(await photo.verifiedBytes(), bytes);
    return (directory, file, photo);
  });
  final captured = fixture!;
  final directory = captured.$1, file = captured.$2;
  final photo = captured.$3;
  addTearDown(() => tester.runAsync(() async { await directory.delete(recursive: true); }));
  final access=Access();final sources=<ImageSource>[];
  await tester.binding.setSurfaceSize(const Size(650,1500));addTearDown(()=>tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(home:ExpensePersonalPage(access:access,pickReceipt:(source)async{sources.add(source);return photo;})));
  await tester.pumpAndSettle();await tester.tap(find.text('写真を撮る'));await tester.pumpAndSettle();
  expect(sources,[ImageSource.camera]);expect(find.text('申請前の領収書プレビュー'),findsOneWidget);expect(access.submitted,isEmpty);
  await tester.enterText(find.widgetWithText(TextField,'内容'),'領収書付き交通費');
  await tester.enterText(find.widgetWithText(TextField,'金額（円）'),'1234');
  await tester.ensureVisible(find.text('申請する'));await tester.tap(find.text('申請する'));await tester.pumpAndSettle();
  expect(access.submitted.length,1);expect(access.draft!.receipt!.localPath,file.path);
  final encoded=access.draft!.encoded;expect(ExpenseSubmission.decode(encoded).encoded,encoded);
  await tester.ensureVisible(find.text('同じ申請を再確認'));await tester.tap(find.text('同じ申請を再確認'));await tester.pumpAndSettle();
  expect(access.submitted.length,2);expect(access.submitted[1].encoded,encoded);
  expect(await tester.runAsync(() => file.exists()),isTrue);expect(tester.takeException(),isNull);
 });
 test('changed local receipt cannot be uploaded on a retry',()async{
  final directory=await Directory.systemTemp.createTemp('expense-camera-integrity-');addTearDown(()=>directory.delete(recursive:true));
  final bytes=base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a6V8AAAAASUVORK5CYII=');
  final file=await File('${directory.path}/receipt.png').writeAsBytes(bytes);
  final photo=ExpenseReceiptAttachment(file.path,sha256.convert(bytes).toString(),bytes.length,'image/png');
  await file.writeAsString('changed');await expectLater(photo.verifiedBytes(),throwsA(isA<StateError>()));
 });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/people/worker_document_page.dart';

void main() {
  testWidgets('manager has a visible requirement creation action', (
    tester,
  ) async {
    var added = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkerDocumentRegistrationActions(
            canManage: true,
            photoEditingAvailable: false,
            onAddRequirement: () => added = true,
          ),
        ),
      ),
    );
    expect(find.text('必要書類の項目を追加'), findsOneWidget);
    await tester.tap(find.text('必要書類の項目を追加'));
    expect(added, isTrue);
    expect(find.textContaining('保存後'), findsOneWidget);
  });
  testWidgets('viewer sees own registration guidance without manager action', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkerDocumentRegistrationActions(
            canManage: false,
            photoEditingAvailable: true,
            onAddRequirement: () => fail('not permitted'),
          ),
        ),
      ),
    );
    expect(find.text('必要書類の項目を追加'), findsNothing);
    expect(find.textContaining('自分の書類を登録'), findsOneWidget);
  });
}

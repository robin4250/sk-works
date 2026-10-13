import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sk_works/features/expenses/expense_claim.dart';
import 'package:sk_works/features/expenses/expense_management_repository.dart';
import 'package:sk_works/features/expenses/expense_review_flow_dialog.dart';
import 'package:sk_works/features/expenses/expense_review_detail_page.dart';
import 'package:sk_works/features/expenses/expense_settlement_choice.dart';

ExpenseClaim claim() => ExpenseClaim(id: 'claim', companyId: 'company', applicantId: 'worker',
  applicantName: '本人', incurredOn: DateTime(2026,9,30), submittedAt: DateTime.utc(2026,9,30,15),
  description: '領収書の交通費', amountYen: 1234, approval: ExpenseApproval.pending,
  allocation: ExpenseAllocation(ExpenseCategory.unallocated));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('atomic command persists exact draft and verifies the final receipt', () async {
    String? endpoint; Map<String, dynamic>? sent;
    final repository = ExpenseManagementRepository(actor: () => 'actor', rpc: (name, params) async {
      endpoint = name; sent = params;
      return {'id':'claim','company_id':'company','revision':2,'allocation':'other','counterparty_id':null,
        'approval':'approved','reviewed_by':'actor','reviewed_at':'2026-10-13T01:00:00+09:00','cost_allocation_current':false,
        'review_action':'approve','review_memo':'確認済み','settlement_method':'paid','settlement_month':'2026-10-01'};
    });
    final command = ExpenseReviewCommand.create('actor','company','claim',1,'approve',ExpenseAllocation(ExpenseCategory.other),
      settlement: ExpenseSettlementChoice(ExpenseSettlementMethod.paid,DateTime.utc(2026,10)), confirmReview:true,memo:'確認済み');
    expect(ExpenseReviewCommand.decode(command.encoded).encoded, command.encoded);
    await repository.execute(command);
    expect(endpoint, 'expense_confirm_review');
    expect(sent!['p_method'], 'paid'); expect(sent!['p_allocation'], 'other');
    expect(sent!.containsKey('p_settlement_month'), isFalse);
    expect(await repository.pending('company'), isNull);
  });
  test('inconsistent final approval receipt preserves the fixed command', () async {
    final repository = ExpenseManagementRepository(actor: () => 'actor', rpc: (_, params) async => {
      'id':'claim','company_id':'company','revision':2,'allocation':'other','counterparty_id':null,
      'approval':'pending','reviewed_by':'actor','reviewed_at':'2026-10-13T01:00:00+09:00','cost_allocation_current':false,
      'review_action':'approve','review_memo':'','settlement_method':'paid','settlement_month':'2026-10-01'});
    final command = ExpenseReviewCommand.create('actor','company','claim',1,'approve',ExpenseAllocation(ExpenseCategory.other),
      settlement: ExpenseSettlementChoice(ExpenseSettlementMethod.paid,DateTime.utc(2026,10)), confirmReview:true,memo:'');
    await expectLater(repository.execute(command), throwsA(isA<StateError>()));
    expect((await repository.pending('company'))!.encoded,command.encoded);
  });
  testWidgets('five steps preserve local choices and write only on final confirmation', (tester) async {
    tester.view.physicalSize=const Size(320,900);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    ExpenseReviewDecision? result;
    await tester.pumpWidget(MaterialApp(builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:const TextScaler.linear(1.3)),child:child!),
      home:Builder(builder:(context)=>Scaffold(body:TextButton(onPressed:()async{
        result=await showDialog<ExpenseReviewDecision>(context:context,builder:(_)=>ExpenseReviewFlowDialog(claim:claim(),destinations:const []));
      },child:const Text('開く'))))));
    Future<void> tap(String label)async{await tester.ensureVisible(find.text(label).last);await tester.tap(find.text(label).last);await tester.pumpAndSettle();}
    await tap('開く'); await tap('次へ');
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton,'次へ')).onPressed,isNull);
    await tap('その他（承認のみ）');await tap('次へ');await tap('支払済み（対象外）');await tap('次へ');
    await tester.enterText(find.byType(TextField),'メモ');await tap('次へ');
    expect(result,isNull);expect(find.text('⑤ 最終確認'),findsOneWidget);
    expect(find.text('精算対象月（申請月）：2026年10月'),findsOneWidget);
    await tap('戻る');expect(find.text('④ メモ'),findsOneWidget);expect(find.text('メモ'),findsOneWidget);
    await tap('次へ');await tap('確定');
    expect(result!.destination!.category,ExpenseCategory.other);expect(result!.settlement!.method,ExpenseSettlementMethod.paid);
    expect(result!.memo,'メモ');expect(tester.takeException(),isNull);
    result=null;await tap('開く');await tap('却下する（メモへ進む）');await tap('次へ');
    expect(find.text('④ メモ'),findsOneWidget);await tester.enterText(find.byType(TextField),'要確認');await tap('次へ');await tap('確定');
    expect(result!.approve,isFalse);expect(result!.destination,isNull);expect(result!.settlement,isNull);expect(result!.memo,'要確認');
    result=null;await tap('開く');await tap('キャンセル');expect(result,isNull);expect(tester.takeException(),isNull);
  });
  testWidgets('rejected detail keeps its memo and edit history actions accessible on narrow screens', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var edited = false, openedHistory = false;
    final rejected = ExpenseClaim(
      id: 'claim', companyId: 'company', applicantId: 'worker',
      applicantName: '本人', incurredOn: DateTime(2026, 9, 30),
      submittedAt: DateTime.utc(2026, 9, 30, 15),
      description: '領収書の交通費', amountYen: 1234,
      approval: ExpenseApproval.rejected,
      allocation: ExpenseAllocation(ExpenseCategory.unallocated),
      reviewMemo: '領収書の内容を確認してください。',
    );
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)), child: child!),
      home: ExpenseReviewDetailPage(claim: rejected,
        onEdit: () async { edited = true; },
        onHistory: () async { openedHistory = true; }),
    ));
    expect(find.text('メモ（却下理由）：領収書の内容を確認してください。'), findsOneWidget);
    expect(find.textContaining('精算方法：'), findsNothing);
    await tester.ensureVisible(find.text('内容を修正する'));
    await tester.tap(find.text('内容を修正する')); await tester.pump();
    await tester.ensureVisible(find.text('履歴を確認'));
    await tester.tap(find.text('履歴を確認')); await tester.pump();
    expect(edited, isTrue); expect(openedHistory, isTrue);
    await tester.tap(find.byTooltip('ヘルプ')); await tester.pumpAndSettle();
    expect(find.text('閉じる'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

}

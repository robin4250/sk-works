import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/expenses/expense_claim.dart';
import 'package:sk_works/features/expenses/expense_claims_page.dart';

ExpenseClaim original({bool deleted=false})=>ExpenseClaim(id:'claim',companyId:'company',applicantId:'worker',applicantName:'本人',incurredOn:DateTime(2026,10,1),submittedAt:DateTime(2026,10,2),description:'経費原本',amountYen:1234,approval:ExpenseApproval.pending,allocation:ExpenseAllocation(ExpenseCategory.unallocated),managerDeleted:deleted);
final enabled=Platform.environment['SKO_EXPENSE_ACTION_IDENTITY_FIXTURE']=='fixture-only';
void main(){
  testWidgets('manager-deleted transition keeps the detail action instead of reusing the removed button style',(tester)async{
    await tester.binding.setSurfaceSize(const Size(800,1400));addTearDown(()=>tester.binding.setSurfaceSize(null));
    final value=ValueNotifier(original());addTearDown(value.dispose);ExpenseClaim? opened;int deleted=0;
    await tester.pumpWidget(MaterialApp(home:ValueListenableBuilder<ExpenseClaim>(valueListenable:value,builder:(_,claim,child)=>ExpenseClaimsPage(claims:ExpenseClaims(companyId:'company',claims:[claim]),reviewFlowEnabled:true,
      onApprove:(_)async{},onReject:(_)async{},onDelete:(_)async{deleted++;},onOpenDetail:(claim)async{opened=claim;}))));
    await tester.pumpAndSettle();expect(find.text('削除'),findsOneWidget);expect(find.text('詳細・履歴'),findsOneWidget);
    value.value=original(deleted:true);await tester.pump();await tester.pumpAndSettle();
    expect(tester.takeException(),null);expect(find.text('削除'),findsNothing);expect(find.textContaining('管理者削除'),findsOneWidget);
    await tester.tap(find.text('詳細・履歴'));await tester.pumpAndSettle();
    expect(opened!.id,'claim');expect(opened!.managerDeleted,true);expect(opened!.approval,ExpenseApproval.pending);expect(opened!.withdrawn,false);expect(deleted,0);expect(tester.takeException(),null);
  },skip:!enabled);
  testWidgets('capability OFF removes only the delete action and preserves the current detail target',(tester)async{
    await tester.binding.setSurfaceSize(const Size(800,1400));addTearDown(()=>tester.binding.setSurfaceSize(null));
    final capability=ValueNotifier(true);addTearDown(capability.dispose);ExpenseClaim? opened;int deleted=0;
    await tester.pumpWidget(MaterialApp(home:ValueListenableBuilder<bool>(valueListenable:capability,builder:(_,allowed,child)=>ExpenseClaimsPage(claims:ExpenseClaims(companyId:'company',claims:[original()]),reviewFlowEnabled:true,
      onApprove:(_)async{},onReject:(_)async{},onDelete:allowed?(_)async{deleted++;}:null,onOpenDetail:(claim)async{opened=claim;}))));
    await tester.pumpAndSettle();expect(find.text('削除'),findsOneWidget);
    capability.value=false;await tester.pump();await tester.pumpAndSettle();
    expect(tester.takeException(),null);expect(find.text('削除'),findsNothing);expect(find.text('詳細・履歴'),findsOneWidget);
    await tester.tap(find.text('詳細・履歴'));await tester.pumpAndSettle();
    expect(opened!.companyId,'company');expect(opened!.id,'claim');expect(opened!.managerDeleted,false);expect(deleted,0);expect(tester.takeException(),null);
  },skip:!enabled);
}

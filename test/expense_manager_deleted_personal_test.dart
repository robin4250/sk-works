import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/expenses/expense_claim.dart';
import 'package:sk_works/features/expenses/expense_personal_page.dart';
import 'package:sk_works/features/expenses/expense_submission_repository.dart';
import 'package:sk_works/features/expenses/expense_personal_change_repository.dart';

ExpenseClaim claim(bool deleted)=>ExpenseClaim(id:'claim',companyId:'company',applicantId:'worker',applicantName:'本人',incurredOn:DateTime(2026,10,1),submittedAt:DateTime(2026,10,2),description:'経費原本',amountYen:1200,approval:ExpenseApproval.approved,allocation:ExpenseAllocation(ExpenseCategory.ownCompany),managerDeleted:deleted);
class Source implements ExpenseSubmissionAccess {
  Source(this.deleted);final bool deleted;
  @override String? get actor=>'actor';
  @override Future<List<Map<String,dynamic>>> scopes()async=>[{'company_id':'company','worker_id':'worker','company_name':'会社','worker_name':'本人'}];
  @override Future<List<ExpenseClaim>> history(String company,String worker,DateTime month)async=>[claim(deleted)];
  @override Future<ExpenseSubmission?> pending(String company,String worker)async=>null;
  @override Future<void> submit(ExpenseSubmission draft)async=>throw StateError('Unexpected submit');
}
class Changes implements ExpensePersonalChangeAccess {
  int calls=0;
  @override Future<ExpensePersonalChange?> pending(String company,String worker)async=>null;
  @override Future<void> send(ExpensePersonalChange command)async{calls++;}
}
void main(){
  test('manager deletion never becomes an applicant withdrawal command',(){
    final original=claim(true);
    expect(original.approval,ExpenseApproval.approved);expect(original.withdrawn,false);
    expect(()=>ExpensePersonalChange.create('actor',original),throwsStateError);
    expect(()=>ExpensePersonalChange.create('actor',original,edit:ExpenseSubmission.create('actor','company','worker',DateTime(2026,10,1),'訂正','1000')),throwsStateError);
  });
  testWidgets('deleted original remains visible with manager label while personal edit and withdrawal controls disappear',(tester)async{
    await tester.binding.setSurfaceSize(const Size(700,1500));addTearDown(()=>tester.binding.setSurfaceSize(null));
    final changes=Changes();await tester.pumpWidget(MaterialApp(home:ExpensePersonalPage(access:Source(true),changes:changes)));await tester.pumpAndSettle();
    expect(find.textContaining('管理者削除'),findsOneWidget);expect(find.text('経費原本'),findsOneWidget);
    expect(find.text('編集'),findsNothing);expect(find.text('削除'),findsNothing);expect(changes.calls,0);
    await tester.ensureVisible(find.text('経費原本'));await tester.tap(find.text('経費原本'));await tester.pumpAndSettle();
    expect(find.text('管理者削除（原本保持）'),findsWidgets);expect(find.text('削除'),findsNothing);expect(changes.calls,0);
  });
  testWidgets('ordinary original retains existing personal edit controls',(tester)async{
    await tester.binding.setSurfaceSize(const Size(700,1500));addTearDown(()=>tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home:ExpensePersonalPage(access:Source(false),changes:Changes())));await tester.pumpAndSettle();
    expect(find.text('編集'),findsOneWidget);expect(find.text('削除'),findsOneWidget);expect(find.textContaining('管理者削除'),findsNothing);
  });
}

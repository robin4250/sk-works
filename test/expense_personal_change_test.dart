import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/expenses/expense_claim.dart';
import 'package:sk_works/features/expenses/expense_personal_change_repository.dart';
import 'package:sk_works/features/expenses/expense_submission_repository.dart';

ExpenseClaim claim() => ExpenseClaim(id:'claim',companyId:'company',applicantId:'worker',applicantName:'本人',
 incurredOn:DateTime(2026,10,1),submittedAt:DateTime(2026,10,2),description:'元の内容',amountYen:100,
 approval:ExpenseApproval.approved,allocation:ExpenseAllocation(ExpenseCategory.customer,counterpartyId:'customer'),revision:7);
ExpensePersonalChange edit() => ExpensePersonalChange.create('actor',claim(),
 edit:ExpenseSubmission.create('actor','company','worker',DateTime(2026,10,3),'養生テープ3巻','1234'));
Map<String,dynamic> result(ExpensePersonalChange c)=>{
 'id':'claim','company_id':'company','applicant_id':'worker','created_by':'actor','revision':8,
 'allocation':'unallocated','counterparty_id':null,'withdrawn':c.withdrawing,
 'approval':c.withdrawing?'rejected':'pending','incurred_on':c.parameters['p_date'],
 'description':c.parameters['p_description'],'amount_yen':c.parameters['p_amount'],
};
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 setUp(()=>SharedPreferences.setMockInitialValues({}));
 test('edit carries expected revision, has fixed UUID, and survives decode',(){
  final c=edit();expect(c.parameters['p_revision'],7);expect(c.parameters['p_action'],'edit');
  expect(ExpensePersonalChange.decode(c.encoded).encoded,c.encoded);c.verify(result(c));
  expect(()=>c.verify({...result(c),'approval':'approved'}),throwsStateError);
  expect(()=>c.verify({...result(c),'revision':9}),throwsStateError);
 });
 test('ambiguous reply persists one exact edit and repeated calls serialize',() async {
  final c=edit();final gate=Completer<dynamic>();var calls=0;
  final repo=ExpensePersonalChangeRepository(actor:()=> 'actor',invoke:(p){calls++;return gate.future;});
  final first=repo.send(c), second=repo.send(c);
  await Future<void>.delayed(Duration.zero);
  expect(calls,1);expect((await repo.pending('company','worker'))!.encoded,c.encoded);
  await expectLater(repo.send(edit()),throwsStateError);
  gate.completeError(TimeoutException('response lost'));
  await expectLater(first,throwsA(isA<TimeoutException>()));await expectLater(second,throwsA(isA<TimeoutException>()));
  final recovery=ExpensePersonalChangeRepository(actor:()=> 'actor',invoke:(p) async {expect(p,c.parameters);return result(c);});
  await recovery.send((await recovery.pending('company','worker'))!);
  expect(await recovery.pending('company','worker'),isNull);
 });
 test('full version rejection clears pending; malformed response retains it',() async {
  final c=edit();final repo=ExpensePersonalChangeRepository(actor:()=> 'actor',invoke:(_) async {throw const PostgrestException(message:'stale',code:'40001');});
  await expectLater(repo.send(c),throwsStateError);expect(await repo.pending('company','worker'),isNull);
  final malformed=ExpensePersonalChangeRepository(actor:()=> 'actor',invoke:(_) async=>{'id':'wrong'});
  await expectLater(malformed.send(c),throwsStateError);expect((await malformed.pending('company','worker'))!.encoded,c.encoded);
 });
 test('actor change blocks sending and withdrawal retains audit status',() async {
  var calls=0;final c=ExpensePersonalChange.create('actor',claim());
  final repo=ExpensePersonalChangeRepository(actor:()=> 'different',invoke:(_) async {calls++;return result(c);});
  await expectLater(repo.send(c),throwsStateError);expect(calls,0);
  c.verify(result(c));expect(c.withdrawing,true);expect(c.parameters['p_amount'],isNull);
  final withdrawn=ExpenseClaim(id:'claim',companyId:'company',applicantId:'worker',applicantName:'本人',
   incurredOn:DateTime(2026,10,1),submittedAt:DateTime(2026,10,2),description:'元の内容',amountYen:100,
   approval:ExpenseApproval.rejected,allocation:ExpenseAllocation(ExpenseCategory.unallocated),withdrawn:true);
  expect(expenseClaimStatusLabel(withdrawn),'取り下げ（削除済み）');expect(withdrawn.isSettlementCandidate,false);
  expect(()=>withdrawn.approve(),throwsStateError);
 });
}

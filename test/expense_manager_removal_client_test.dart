import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:sk_works/features/expenses/expense_claim.dart';
import 'package:sk_works/features/expenses/expense_manager_removal_dialog.dart';
import 'package:sk_works/features/notifications/notification_target_policy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sk_works/features/expenses/expense_manager_removal_repository.dart';
import 'package:sk_works/features/expenses/expense_notification_target.dart';

String id(int n)=>'00000000-0000-0000-0000-${n.toString().padLeft(12,'0')}';
Map<String,dynamic> capability(String sid)=>{'manager_removal_version':1,'manager_removal_enabled':true,'can_manager_remove':true,'manager_removal_session':sid};
Map<String,dynamic> saved(ExpenseRemovalCommand c,{bool finalDocument=false})=>{
  'command_id':c.id,'company_id':c.company,'claim_id':c.claim,'requested_revision':c.revision,
  'deleted_by':c.actor,'manager_deleted':true,'deleted_at':'2026-11-01T00:00:00Z',
  'financial_state':finalDocument?'finalized_original_retained':'withdrawn_unfinalized',
  'correction_required':finalDocument,'notification_id':id(8),'notification_state':'stored'};
class Journal implements ExpenseRemovalJournal {
  final values=<String,String>{};bool loseWrite=false;void Function()? erased;
  @override Future<String?> read(String key)async=>values[key];
  @override Future<void> write(String key,String value)async{if(!loseWrite)values[key]=value;}
  @override Future<void> erase(String key,String expected)async{if(values[key]!=expected)throw StateError('mismatch');values.remove(key);erased?.call();}
}
void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(()=>SharedPreferences.setMockInitialValues({}));
  test('unknown, OFF, malformed bool and different SID never grant deletion',(){
    expect(ExpenseRemovalCapability({},id(4)).enabled,false);
    expect(ExpenseRemovalCapability({...capability(id(4)),'manager_removal_enabled':false},id(4)).enabled,false);
    expect(ExpenseRemovalCapability(capability(id(4)),id(5)).enabled,false);
    expect(()=>ExpenseRemovalCapability({...capability(id(4)),'can_manager_remove':'true'},id(4)),throwsFormatException);
  });
  test('uncertain send preserves exact command, new SID observes without re-send',()async{
    String? sid=id(4);final calls=<String>[];
    final command=ExpenseRemovalCommand.create(id(1),id(2),id(3),1,sid,'訂正');
    final repo=ExpenseManagerRemovalRepository(actor:()=>id(1),session:()=>sid,rpc:(name,params)async{
      calls.add(name);if(name=='expense_manager_remove')throw StateError('lost response');return saved(command,finalDocument:true);});
    await expectLater(repo.submit(command,ExpenseRemovalCapability(capability(sid),sid)),throwsStateError);
    expect((await repo.pending(id(2)))!.encoded,command.encoded);
    sid=id(5);
    final result=await repo.observe(command);
    expect(result!.correctionRequired,true);expect(await repo.pending(id(2)),null);
    expect(calls,['expense_manager_remove','expense_manager_removal_result']);
  });
  test('missing result remains unknown and blocks a new send',()async{
    final command=ExpenseRemovalCommand.create(id(1),id(2),id(3),1,id(4),'訂正');int mutations=0;
    final repo=ExpenseManagerRemovalRepository(actor:()=>id(1),session:()=>id(4),rpc:(name,p)async{
      if(name=='expense_manager_remove'){mutations++;throw StateError('lost');}return null;});
    final cap=ExpenseRemovalCapability(capability(id(4)),id(4));
    await expectLater(repo.submit(command,cap),throwsStateError);expect(await repo.observe(command),null);
    await expectLater(repo.submit(command,cap),throwsStateError);expect(mutations,1);expect(await repo.pending(id(2)),isNotNull);
  });
  test('mismatched response does not clear journal or claim success',()async{
    final c=ExpenseRemovalCommand.create(id(1),id(2),id(3),1,id(4),'訂正');
    final repo=ExpenseManagerRemovalRepository(actor:()=>id(1),session:()=>id(4),rpc:(n,p)async=>{...saved(c),'claim_id':id(99)});
    await expectLater(repo.submit(c,ExpenseRemovalCapability(capability(id(4)),id(4))),throwsFormatException);
    expect(await repo.pending(id(2)),isNotNull);
  });
  test('actor change after request cannot consume another account result',()async{
    String? actor=id(1);final c=ExpenseRemovalCommand.create(actor,id(2),id(3),1,id(4),'訂正');
    final repo=ExpenseManagerRemovalRepository(actor:()=>actor,session:()=>id(4),rpc:(n,p)async{actor=id(9);return saved(c);});
    await expectLater(repo.submit(c,ExpenseRemovalCapability(capability(id(4)),id(4))),throwsStateError);
    actor=id(1);expect(await repo.pending(id(2)),isNotNull);
  });
  test('no capability or new SID can dispatch an old command',()async{
    int calls=0;final c=ExpenseRemovalCommand.create(id(1),id(2),id(3),1,id(4),'訂正');
    final repo=ExpenseManagerRemovalRepository(actor:()=>id(1),session:()=>id(5),rpc:(n,p)async{calls++;return saved(c);});
    await expectLater(repo.submit(c,ExpenseRemovalCapability(capability(id(5)),id(5))),throwsStateError);
    expect(calls,0);
  });
  test('deletion notice is whitelisted read-only history with separate financial correction',(){
    final raw={'notification_id':id(8),'action_key':'expense_manager_deleted','action_id':id(7),'company_id':id(2),'claim_id':id(3),'manager_deleted':true,
      'description':'経費','amount_yen':1200,'incurred_on':'2026-10-01','deleted_at':'2026-11-01T00:00:00Z','financial_state':'finalized_original_retained','correction_required':true,'receipt_object_path':'private/raw'};
    final parsed=parseExpenseNotificationTarget(raw,notificationId:id(8),actionKey:'expense_manager_deleted',actionId:id(7));
    expect(parsed['correction_required'],true);expect(parsed.containsKey('receipt_object_path'),false);
    expect(()=>parseExpenseNotificationTarget({...raw,'correction_required':'true'},notificationId:id(8),actionKey:'expense_manager_deleted',actionId:id(7)),throwsFormatException);
  });
  test('deleted claims cannot enter approval or settlement and retain original financial state',(){
    final claim=ExpenseClaim(id:id(3),companyId:id(2),applicantId:id(9),applicantName:'本人',incurredOn:DateTime(2026,10,1),submittedAt:DateTime(2026,10,2),description:'経費',amountYen:1200,approval:ExpenseApproval.approved,allocation:ExpenseAllocation(ExpenseCategory.ownCompany),managerDeleted:true);
    expect(claim.approval,ExpenseApproval.approved);expect(claim.withdrawn,false);
    expect(claim.isSettlementCandidate,false);expect(()=>claim.approve(),throwsStateError);expect(()=>claim.reject(),throwsStateError);
    expect(expenseClaimStatusLabel(claim),contains('管理者削除'));
  });
  test('typed deletion route requires a saved command UUID',(){
    expect(notificationTargetIsValid('expense_manager_deleted',null),false);
    expect(notificationTargetIsValid('expense_manager_deleted','other'),false);
    expect(notificationTargetIsValid('expense_manager_deleted',id(7)),true);
  });
  testWidgets('confirmation preserves finalized-original warning and needs an explicit reason and tap',(tester)async{
    final claim=ExpenseClaim(id:id(3),companyId:id(2),applicantId:id(9),applicantName:'本人',incurredOn:DateTime(2026,10,1),submittedAt:DateTime(2026,10,2),description:'経費',amountYen:1200,approval:ExpenseApproval.approved,allocation:ExpenseAllocation(ExpenseCategory.ownCompany));
    String? reason;
    await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:TextButton(onPressed:()async{reason=await showDialog<String>(context:context,builder:(_)=>ExpenseManagerRemovalDialog(claim:claim));},child:const Text('開く'))))));
    await tester.tap(find.text('開く'));await tester.pumpAndSettle();
    expect(find.textContaining('別途訂正が必要'),findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton,'削除を確定')).onPressed,null);
    await tester.enterText(find.byType(TextField),' テスト申請の訂正 ');await tester.pump();
    expect(reason,null);await tester.tap(find.text('削除を確定'));await tester.pumpAndSettle();expect(reason,'テスト申請の訂正');
  });

  test('Auth A to B to A event permanently retires the in-flight adoption',()async{
    final events=StreamController<void>.broadcast(sync:true);addTearDown(events.close);
    final c=ExpenseRemovalCommand.create(id(1),id(2),id(3),1,id(4),'訂正');
    final repo=ExpenseManagerRemovalRepository(actor:()=>id(1),session:()=>id(4),invalidations:events.stream,rpc:(n,p)async{events.add(null);events.add(null);return saved(c);});
    addTearDown(repo.dispose);
    await expectLater(repo.submit(c,ExpenseRemovalCapability(capability(id(4)),id(4))),throwsStateError);
    expect((await repo.pending(id(2)))!.encoded,c.encoded);
  });
  test('journal readback failure makes zero mutation RPC calls',()async{
    final journal=Journal()..loseWrite=true;int calls=0;
    final c=ExpenseRemovalCommand.create(id(1),id(2),id(3),1,id(4),'訂正');
    final repo=ExpenseManagerRemovalRepository(actor:()=>id(1),session:()=>id(4),journal:journal,rpc:(n,p)async{calls++;return saved(c);});addTearDown(repo.dispose);
    await expectLater(repo.submit(c,ExpenseRemovalCapability(capability(id(4)),id(4))),throwsStateError);expect(calls,0);
  });
  test('Auth change while clearing restores the journal and requires result observation',()async{
    final events=StreamController<void>.broadcast(sync:true);addTearDown(events.close);
    final journal=Journal()..erased=()=>events.add(null);
    final c=ExpenseRemovalCommand.create(id(1),id(2),id(3),1,id(4),'訂正');
    final repo=ExpenseManagerRemovalRepository(actor:()=>id(1),session:()=>id(4),invalidations:events.stream,journal:journal,rpc:(n,p)async=>saved(c));addTearDown(repo.dispose);
    await expectLater(repo.submit(c,ExpenseRemovalCapability(capability(id(4)),id(4))),throwsStateError);
    expect((await repo.pending(id(2)))!.encoded,c.encoded);
  });
  test('result containing extra error metadata cannot become confirmed success',(){
    final c=ExpenseRemovalCommand.create(id(1),id(2),id(3),1,id(4),'訂正');
    expect(()=>ExpenseRemovalResult({...saved(c),'error':'unavailable'},c),throwsFormatException);
  });

  testWidgets('Auth retirement and parent stream completion mask an open deletion modal without closing another modal',(tester)async{
    final events=StreamController<void>.broadcast(sync:true);
    final claim=ExpenseClaim(id:id(3),companyId:id(2),applicantId:id(9),applicantName:'本人',incurredOn:DateTime(2026,10,1),submittedAt:DateTime(2026,10,2),description:'機密経費',amountYen:1200,approval:ExpenseApproval.approved,allocation:ExpenseAllocation(ExpenseCategory.ownCompany));
    late BuildContext host;
    await tester.pumpWidget(MaterialApp(home:Builder(builder:(context){host=context;return Scaffold(body:TextButton(onPressed:()=>showDialog<String>(context:context,builder:(_)=>ExpenseManagerRemovalDialog(claim:claim,invalidations:events.stream)),child:const Text('開く')));} )));
    await tester.tap(find.text('開く'));await tester.pumpAndSettle();await tester.enterText(find.byType(TextField),'理由');
    events.add(null);await tester.pumpAndSettle();
    expect(find.text('機密経費'),findsNothing);expect(find.byType(TextField),findsNothing);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton,'削除を確定')).onPressed,null);
    unawaited(showDialog<void>(context:host,builder:(_)=>const AlertDialog(title:Text('別の画面'))));await tester.pumpAndSettle();
    await events.close();await tester.pumpAndSettle();expect(find.text('別の画面'),findsOneWidget);expect(tester.takeException(),null);
  });

}

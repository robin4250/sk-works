import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/features/expenses/expense_manager_removal_repository.dart';
import '../lib/features/expenses/expense_notification_target.dart';

String id(int n)=>'00000000-0000-0000-0000-${n.toString().padLeft(12,'0')}';
Map<String,dynamic> capability(String sid)=>{'manager_removal_version':1,'manager_removal_enabled':true,'can_manager_remove':true,'manager_removal_session':sid};
Map<String,dynamic> saved(ExpenseRemovalCommand c,{bool finalDocument=false})=>{
  'command_id':c.id,'company_id':c.company,'claim_id':c.claim,'requested_revision':c.revision,
  'deleted_by':c.actor,'manager_deleted':true,'deleted_at':'2026-11-01T00:00:00Z',
  'financial_state':finalDocument?'finalized_original_retained':'withdrawn_unfinalized',
  'correction_required':finalDocument,'notification_id':id(8),'notification_state':'stored'};
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
    final command=ExpenseRemovalCommand.create(id(1),id(2),id(3),1,sid!,'訂正');
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
    String? actor=id(1);final c=ExpenseRemovalCommand.create(actor!,id(2),id(3),1,id(4),'訂正');
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
}

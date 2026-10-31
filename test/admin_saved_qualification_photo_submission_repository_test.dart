import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/qualifications/admin_saved_qualification_photo_submission_repository.dart';

const actor='10000000-0000-0000-0000-000000000001';
const company='10000000-0000-0000-0000-000000000002';
const worker='10000000-0000-0000-0000-000000000003';
const target='10000000-0000-0000-0000-000000000004';
const sessionA='10000000-0000-0000-0000-000000000005';
const sessionB='10000000-0000-0000-0000-000000000006';
Map<String,dynamic> row()=>{'id':target,'company_id':company,'worker_id':worker,
  'attachment_path':'synthetic/front','attachment_back_path':'synthetic/back',
  'attachment_extra_paths':<String>[]};
class Port implements AdminSavedQualificationPort {
  @override
  String actor='10000000-0000-0000-0000-000000000001';
  @override
  String sid=sessionA;
  bool current=true,enabled=true,failWrite=false,unknownPrepare=false,unknownSubmit=false;
  bool malformed=false,legacyCapability=false;
  String status='draft';
  final journal=<String,String>{};
  final calls=<String>[];
  Map<String,dynamic>? request;
  @override
  Future<void> check() async {if(!current)throw StateError('retired');}
  @override
  Future<String?> readJournal(String key) async=>journal[key];
  @override
  Future<void> writeJournal(String key,String value) async{
    if(failWrite)throw StateError('disk unavailable');
    journal[key]=value;
  }
  @override
  Future<void> clearJournal(String key) async{journal.remove(key);}
  Map<String,dynamic> result()=>{'version':1,'id':request!['request_id'],
    'target_id':target,'requested_by':actor,'status':status,'cancelled':false,
    'reason':null,'photo_paths':request!['selected_paths'],'upload_paths':<Object>[]};
  @override
  Future<Object?> call(String action,Map<String,dynamic> data) async {
    await check();calls.add(action);
    if(action=='admin_saved_photo_capability'){return {
      'version':legacyCapability?1:2,if(!legacyCapability)'expected_photo_paths_required':true,'contract':'qualification_admin_saved_photos','company_id':company,
      'actor_id':actor,'photo_submission_available':enabled,'photo_upload_allowed':false,
      'max_photos':20,'self_approval_allowed':false};}
    if(action=='prepare_admin_saved_photos'){
      request=jsonDecode(journal.values.single) as Map<String,dynamic>;
      expect(request!['stage'],'prepare_started');
      expect(data['expected_photo_paths'],['synthetic/front','synthetic/back']);
      expect(data['request_id'],request!['request_id']);
      if(unknownPrepare)throw StateError('after commit unknown');
      return malformed?<String,dynamic>{}:result();
    }
    if(action=='submit'){
      expect(data['id'],request!['request_id']);
      status='pending';if(unknownSubmit)throw StateError('after commit unknown');
      return result();
    }
    if(action=='get_photos'){
      expect(data['id'],request!['request_id']);return malformed?<String,dynamic>{}:result();
    }
    throw StateError('Unexpected action $action');
  }
}
void main(){
  test('persist fixed intent before prepare, exact baseline, submit then reconcile receipt',()async{
    final p=Port();final repo=AdminSavedQualificationSubmissionRepository(p,AdminSavedQualificationTarget(row()));
    final result=await repo.submit(['synthetic/back']);
    expect(result.status,'pending');expect(p.calls,['admin_saved_photo_capability','prepare_admin_saved_photos','submit','get_photos']);
    expect((await repo.journal())!['stage'],'pending');
    expect(p.journal.values.single,contains('synthetic/front'));
  });
  test('prepare unknown retains fixed ID; restart/new SID recovery is read only',()async{
    final p=Port()..unknownPrepare=true;
    final repo=AdminSavedQualificationSubmissionRepository(p,AdminSavedQualificationTarget(row()));
    await expectLater(repo.submit([]),throwsStateError);
    final original=await repo.journal();p.sid=sessionB;p.calls.clear();
    final reopened=AdminSavedQualificationSubmissionRepository(p,AdminSavedQualificationTarget(row()));
    expect((await reopened.reconcile())!.status,'draft');
    expect(p.calls,['get_photos']);
    expect((await reopened.journal())!['request_id'],original!['request_id']);
    expect((await reopened.journal())!['session_id'],sessionA);
    await expectLater(reopened.submit([]),throwsStateError);
    expect(p.calls,['get_photos']);
  });
  test('submit unknown is not resent and pending readback is distinct from draft',()async{
    final p=Port()..unknownSubmit=true;
    final repo=AdminSavedQualificationSubmissionRepository(p,AdminSavedQualificationTarget(row()));
    await expectLater(repo.submit(['synthetic/front']),throwsStateError);
    p.calls.clear();expect((await repo.reconcile())!.status,'pending');
    expect(p.calls,['get_photos']);
    await expectLater(repo.acknowledgeFinal(),throwsStateError);
    expect(await repo.journal(),isNotNull);
  });
  test('malformed prepare result retains journal, no submit fallback',()async{
    final p=Port()..malformed=true;
    final repo=AdminSavedQualificationSubmissionRepository(p,AdminSavedQualificationTarget(row()));
    await expectLater(repo.submit([]),throwsStateError);
    expect(p.calls, ['admin_saved_photo_capability','prepare_admin_saved_photos']);
    expect(await repo.journal(),isNotNull);
    await expectLater(repo.reconcile(),throwsStateError);
  });
  test('journal write failure prevents all mutation',()async{
    final p=Port()..failWrite=true;
    final repo=AdminSavedQualificationSubmissionRepository(p,AdminSavedQualificationTarget(row()));
    await expectLater(repo.submit([]),throwsStateError);
    expect(p.calls,['admin_saved_photo_capability']);
  });
  test('capability unavailable never falls back to personal or direct writes',()async{
    final p=Port()..enabled=false;
    final repo=AdminSavedQualificationSubmissionRepository(p,AdminSavedQualificationTarget(row()));
    await expectLater(repo.submit([]),throwsStateError);
    expect(p.calls,['admin_saved_photo_capability']);expect(p.journal,isEmpty);
  });
  test('old backend ignoring extra expected baseline is never given a mutation',()async{
    final p=Port()..legacyCapability=true;
    final repo=AdminSavedQualificationSubmissionRepository(p,AdminSavedQualificationTarget(row()));
    await expectLater(repo.submit([]),throwsStateError);
    expect(p.calls,['admin_saved_photo_capability']);expect(p.journal,isEmpty);
  });
  test('lease retirement blocks capability, mutation and reconciliation',()async{
    final p=Port()..current=false;
    final repo=AdminSavedQualificationSubmissionRepository(p,AdminSavedQualificationTarget(row()));
    await expectLater(repo.submit([]),throwsStateError);
    await expectLater(repo.reconcile(),throwsStateError);expect(p.calls,isEmpty);
  });
  test('corrupt journal is unknown and never replaced',()async{
    final p=Port();final repo=AdminSavedQualificationSubmissionRepository(p,AdminSavedQualificationTarget(row()));
    p.journal[repo.journalKey]='{}';
    await expectLater(repo.submit([]),throwsStateError);
    await expectLater(repo.reconcile(),throwsStateError);
    expect(p.journal[repo.journalKey],'{}');expect(p.calls,isEmpty);
  });
  test('final acknowledgement archives exact receipt before clearing active journal',()async{
    final p=Port();final repo=AdminSavedQualificationSubmissionRepository(p,AdminSavedQualificationTarget(row()));
    await repo.submit([]);final id=(await repo.journal())!['request_id'];p.status='approved';
    await repo.acknowledgeFinal();
    expect(await repo.journal(),isNull);expect(p.journal.keys.single,endsWith('.receipt.$id'));
    expect(jsonDecode(p.journal.values.single)['stage'],'approved');
  });
  test('baseline strict shape rejects missing sides, duplicates and non-path values',(){
    for(final bad in [
      row()..remove('attachment_extra_paths'),
      row()..['attachment_back_path']='synthetic/front',
      row()..['attachment_extra_paths']=[4],
      row()..['company_id']='bad',
    ]){expect(()=>AdminSavedQualificationTarget(bad),throwsA(anything));}
  });
  test('result wrong request/target/requester/paths/upload/status is unknown',()async{
    final p=Port();final repo=AdminSavedQualificationSubmissionRepository(p,AdminSavedQualificationTarget(row()));
    await repo.submit([]);final journal=(await repo.journal())!;
    for(final entry in {'version':'1','id':worker,'target_id':worker,'requested_by':worker,
      'photo_paths':['foreign'],'upload_paths':[{}],'status':'sent','cancelled':null}.entries){
      expect(()=>AdminSavedQualificationResult.parse({...p.result(),entry.key:entry.value},journal),
        throwsStateError,reason:entry.key);
    }
  });
}

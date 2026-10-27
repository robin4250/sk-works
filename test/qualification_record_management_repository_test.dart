import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/qualifications/qualification_record_management_repository.dart';

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(()=>SharedPreferences.setMockInitialValues({}));
  test('legacy and personal capabilities never enable privacy-v2 mutations',()async{
    for(final cap in [{'version':1,'photo_submission_available':true},{..._Fixture.capability,'version':1}]){
      final f=_Fixture()..responseCapability=cap;addTearDown(f.dispose);
      expect(await f.repository.available('company'),false);
      await expectLater(f.save(),throwsStateError);
      expect(f.actions.every((a)=>a=='capability'),true);
    }
  });
  test('lost apply reply confirms same committed operation without approval',()async{
    final f=_Fixture()..loseApplyReply=true;addTearDown(f.dispose);
    expect((await f.save())['status'],'applied');
    expect(f.actions.where((a)=>a=='apply'),hasLength(1));
    expect(f.actions,isNot(contains('approve')));
    expect(await f.repository.pending('company'),isNull);
    expect(f.applyPayloads.single,{'company_id':'company','request_id':f.preparedIds.single});
  });
  test('uncertain prepare stores only opaque IDs and survives repository recreation',()async{
    final f=_Fixture()..losePrepareReply=true;addTearDown(f.dispose);
    await expectLater(f.save(),throwsStateError);
    final ref=await f.repository.pending('company');expect(ref,isNotNull);
    final prefs=await SharedPreferences.getInstance();
    final persisted=prefs.getString(_Fixture.key)!;
    for(final text in ['expected_snapshot','certificate_number','issuer','notes','corrected','private-photo.jpg']){
      expect(persisted.contains(text),false,reason:'personal command must remain server-side: $text');
    }
    expect(jsonDecode(persisted),ref);
    await f.repository.dispose();f.recreate();f.losePrepareReply=false;
    expect((await f.repository.recover('company'))['request_id'],ref!['request_id']);
    expect(f.preparedIds,hasLength(1),reason:'recovery needs no personal payload on the client');
    expect(f.serverCommand!['expected_snapshot'],_Fixture.snapshot);
    expect(await f.repository.pending('company'),isNull);
  });
  test('lost request before prepare can be cancelled without deleting a qualification',()async{
    final f=_Fixture()..dropBeforePrepare=true;addTearDown(f.dispose);
    await expectLater(f.save(),throwsStateError);
    await expectLater(f.repository.recover('company'),throwsA(isA<PostgrestException>()));
    expect(await f.repository.pending('company'),isNotNull);
    expect((await f.repository.cancelUncertain('company'))['status'],'cancelled');
    expect(await f.repository.pending('company'),isNull);
    expect(f.receipt,isNull);
    expect(f.tombstone,true);
  });
  test('A to B to A invalidates captured repository and in-flight response',()async{
    final f=_Fixture();addTearDown(f.dispose);
    final reply=Completer<Object?>();f.capabilityReply=reply.future;
    final checking=f.repository.available('company');
    f.actor='other';f.events.add('other');f.actor='actor';f.events.add('actor');reply.complete(_Fixture.capability);
    await expectLater(checking,throwsStateError);
    final before=f.actions.length;await expectLater(f.save(),throwsStateError);expect(f.actions.length,before);
  });
  test('mismatched applied target never clears the opaque reference',()async{
    final f=_Fixture()..wrongNestedTarget=true;addTearDown(f.dispose);
    await expectLater(f.save(),throwsStateError);
    expect(await f.repository.pending('company'),isNotNull);
  });
  test('definite first snapshot rejection clears only the rejected operation',()async{
    final f=_Fixture()..rejectStale=true;addTearDown(f.dispose);
    await expectLater(f.save(),throwsA(isA<PostgrestException>()));
    expect(await f.repository.pending('company'),isNull);
  });
  test('OFF still confirms an already committed result',()async{
    final f=_Fixture()..loseApplyReply=true..loseGetReply=true;addTearDown(f.dispose);
    await expectLater(f.save(),throwsStateError);f.stopped=true;f.loseGetReply=false;
    expect((await f.repository.recover('company'))['status'],'applied');
    expect(await f.repository.pending('company'),isNull);
  });
  test('expired server command clears reference without reporting saved',()async{
    final f=_Fixture()..losePrepareReply=true;addTearDown(f.dispose);
    await expectLater(f.save(),throwsStateError);f.expired=true;
    await expectLater(f.repository.recover('company'),throwsStateError);
    expect(await f.repository.pending('company'),isNull);
    expect(f.receipt,isNull);
  });
  test('old unreleased full-command key is removed only after server confirmation',()async{
    final f=_Fixture();addTearDown(f.dispose);
    final prefs=await SharedPreferences.getInstance();
    await prefs.setString(_Fixture.legacyKey,jsonEncode({'version':1,'actor_id':'actor',
      'company_id':'company','request_id':'legacy-request','target_id':'target','operation':'update',
      'expected_snapshot':_Fixture.snapshot,'fields':_Fixture.fields}));
    f.holdApply=Completer<void>();
    final recovering=f.repository.recover('company');await f.applyEntered.future;
    expect(prefs.getString(_Fixture.legacyKey),isNull);
    expect(prefs.getString(_Fixture.key)!.contains('private-photo.jpg'),false);
    expect(prefs.getString(_Fixture.key)!.contains('corrected'),false);
    f.holdApply!.complete();
    expect((await recovering)['request_id'],'legacy-request');
    expect(f.preparedIds,['legacy-request']);
    expect(prefs.getString(_Fixture.key),isNull);
  });
}

class _Fixture{
  _Fixture(){recreate();}
  static const key='sko.qualification.management.pending.v2.actor.company';
  static const legacyKey='sko.qualification.management.pending.v1.actor.company';
  static const snapshot=<String,dynamic>{'id':'target','company_id':'company','worker_id':'worker',
    'qualification_master_id':'master','notes':'original','attachment_path':'private-photo.jpg'};
  static const fields=<String,dynamic>{'certificate_number':'new','issuer':'issuer','issued_at':null,
    'expires_at':null,'notes':'corrected'};
  static const capability={'version':2,'contract':'qualification_direct_management','company_id':'company',
    'actor_id':'actor','available':true};
  String actor='actor';
  final events=StreamController<String?>.broadcast(sync:true);
  late QualificationRecordManagementRepository repository;
  Object? responseCapability=capability;
  Future<Object?>? capabilityReply;
  final actions=<String>[];
  final preparedIds=<Object?>[];
  final applyPayloads=<Map<String,dynamic>>[];
  final applyEntered=Completer<void>();
  Completer<void>? holdApply;
  Map<String,dynamic>? serverCommand,receipt;
  bool losePrepareReply=false,dropBeforePrepare=false,loseApplyReply=false,loseGetReply=false,
    wrongNestedTarget=false,rejectStale=false,stopped=false,tombstone=false,expired=false;
  void recreate(){repository=QualificationRecordManagementRepository.forTesting(actor:()=>actor,
    authChanges:events.stream,rpc:_rpc);}
  Future<void> dispose()async{await repository.dispose();await events.close();}
  Map<String,dynamic> _pending(Map<String,dynamic> data,String status)=>{
    'version':2,'contract':'qualification_management_pending','status':status,
    'request_id':data['request_id'],'company_id':'company','actor_id':'actor','target_id':data['target_id']??'target',
    'worker_id':data['worker_id']??'worker','qualification_master_id':data['qualification_master_id']??'master',
    'operation':data['operation']??'update','expires_at':'2026-10-27T12:00:00Z'};
  Future<Object?> _rpc(String action,Map<String,dynamic> data)async{
    actions.add(action);
    if(action=='capability')return capabilityReply??responseCapability;
    if(action=='prepare'){
      if(rejectStale)throw const PostgrestException(message:'stale',code:'40001');
      if(dropBeforePrepare)throw StateError('synthetic request never arrived');
      preparedIds.add(data['request_id']);serverCommand=Map.of(data);
      if(losePrepareReply)throw StateError('synthetic lost prepare response');
      return _pending(data,tombstone?'cancelled':'prepared');
    }
    if(action=='apply'){
      applyPayloads.add(Map.of(data));
      if(!applyEntered.isCompleted)applyEntered.complete();
      if(holdApply!=null)await holdApply!.future;
      if(receipt!=null)return Map.of(receipt!);
      if(stopped||serverCommand==null||expired)throw const PostgrestException(message:'unavailable',code:'55000');
      receipt={'version':1,'contract':'qualification_direct_management','status':'applied',
        'request_id':data['request_id'],'company_id':'company','actor_id':'actor','target_id':'target','operation':'update',
        'before':snapshot,'after':{...snapshot,...fields,if(wrongNestedTarget)'id':'another-target'}};
      if(loseApplyReply)throw StateError('synthetic lost apply response');
      return Map.of(receipt!);
    }
    if(action=='get'){
      if(loseGetReply)throw StateError('synthetic lost result');
      if(receipt!=null)return Map.of(receipt!);
      if(expired)return _pending(data,'expired');
      if(serverCommand!=null)return _pending(data,'prepared');
      throw const PostgrestException(message:'missing',code:'42501');
    }
    if(action=='cancel'){
      if(receipt!=null)return Map.of(receipt!);
      tombstone=true;return _pending(data,'cancelled');
    }
    throw StateError('Unexpected action $action');
  }
  Future<Map<String,dynamic>> save()=>repository.save(companyId:'company',operation:'update',
    targetId:'target',snapshot:snapshot,fields:fields);
}

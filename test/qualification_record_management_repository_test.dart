import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/qualifications/qualification_record_management_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('personal photo capability never enables management mutations', () async {
    final f = _Fixture()..capability = {'version':1,'photo_submission_available':true};
    addTearDown(f.dispose);
    expect(await f.repository.available('company'), isFalse);
    await expectLater(f.save(), throwsStateError);
    expect(f.actions.every((a)=>a=='capability'), isTrue);
    expect(await f.repository.pending('company'), isNull);
  });
  test('lost apply reply confirms same committed operation without approval', () async {
    final f = _Fixture()..loseApplyReply = true;
    addTearDown(f.dispose);
    final saved = await f.save();
    expect(saved['status'],'applied');
    expect(f.actions.where((a)=>a=='apply'),hasLength(1));
    expect(f.actions, isNot(contains('approve')));
    expect(f.actions, isNot(contains('submit')));
    expect(await f.repository.pending('company'),isNull);
  });
  test('uncertain request survives recreation with same ID, fields and snapshot', () async {
    final f = _Fixture()..loseBeforeCommit=true;
    addTearDown(f.dispose);
    await expectLater(f.save(),throwsStateError);
    final pending=await f.repository.pending('company');
    expect(pending,isNotNull);
    await f.repository.dispose();f.recreate();f.loseBeforeCommit=false;
    final result=await f.repository.recover('company');
    expect(result['request_id'],pending!['request_id']);
    expect(f.appliedIds.toSet(),{pending['request_id']});
    expect(f.lastCommand!['expected_snapshot'],_Fixture.snapshot);
    expect(await f.repository.pending('company'),isNull);
  });
  test('A to B to A invalidates captured repository and in-flight response', () async {
    final f=_Fixture();addTearDown(f.dispose);
    final reply=Completer<Object?>();f.capabilityReply=reply.future;
    final checking=f.repository.available('company');
    f.actor='other';f.events.add('other');f.actor='actor';f.events.add('actor');
    reply.complete(_Fixture.validCapability);
    await expectLater(checking,throwsStateError);
    final calls=f.actions.length;await expectLater(f.save(),throwsStateError);
    expect(f.actions.length,calls);
  });
  test('mismatched nested target does not clear uncertain operation', () async {
    final f=_Fixture()..wrongNestedTarget=true;addTearDown(f.dispose);
    await expectLater(f.save(),throwsStateError);
    expect(await f.repository.pending('company'),isNotNull);
  });
  test('definite first snapshot rejection clears only rejected local command', () async {
    final f=_Fixture()..rejectStale=true;addTearDown(f.dispose);
    await expectLater(f.save(),throwsA(isA<PostgrestException>()));
    expect(await f.repository.pending('company'),isNull);
  });
  test('OFF recovery can confirm an already committed outcome', () async {
    final f=_Fixture()..loseApplyReply=true..loseGetReply=true;addTearDown(f.dispose);
    await expectLater(f.save(),throwsStateError);
    f.stopped=true;f.loseGetReply=false;
    expect((await f.repository.recover('company'))['status'],'applied');
    expect(await f.repository.pending('company'),isNull);
  });
}

class _Fixture {
  _Fixture(){recreate();}
  static const snapshot=<String,dynamic>{'id':'target','company_id':'company',
    'worker_id':'worker','qualification_master_id':'master','notes':'original'};
  static const validCapability={'version':1,'contract':'qualification_direct_management',
    'company_id':'company','actor_id':'actor','available':true};
  String actor='actor';
  final events=StreamController<String?>.broadcast(sync:true);
  late QualificationRecordManagementRepository repository;
  Object? capability=validCapability;
  Future<Object?>? capabilityReply;
  final actions=<String>[];
  final appliedIds=<Object?>[];
  Map<String,dynamic>? lastCommand;
  Map<String,dynamic>? receipt;
  bool loseApplyReply=false,loseBeforeCommit=false,loseGetReply=false,
    wrongNestedTarget=false,rejectStale=false,stopped=false;
  void recreate(){repository=QualificationRecordManagementRepository.forTesting(
    actor:()=>actor,authChanges:events.stream,rpc:_rpc);}
  Future<void> dispose()async{await repository.dispose();await events.close();}
  Future<Object?> _rpc(String action,Map<String,dynamic> data)async{
    actions.add(action);
    if(action=='capability')return capabilityReply??capability;
    if(action=='apply'){
      lastCommand=Map.of(data);appliedIds.add(data['request_id']);
      if(stopped)throw const PostgrestException(message:'stopped',code:'55000');
      if(rejectStale)throw const PostgrestException(message:'stale',code:'40001');
      if(loseBeforeCommit)throw StateError('synthetic lost request');
      receipt??={'version':1,'contract':'qualification_direct_management','status':'applied',
        'request_id':data['request_id'],'company_id':'company','actor_id':'actor',
        'target_id':data['target_id'],'operation':data['operation'],
        'before':snapshot,'after':{...snapshot,...(data['fields'] as Map),
          if(wrongNestedTarget)'id':'another-target'}};
      if(loseApplyReply)throw StateError('synthetic lost apply reply');
      return Map.of(receipt!);
    }
    if(action=='get'){
      if(loseGetReply||receipt==null)throw StateError('synthetic unknown result');
      return Map.of(receipt!);
    }
    throw StateError('Unexpected management action $action');
  }
  Future<Map<String,dynamic>> save()=>repository.save(companyId:'company',operation:'update',
    targetId:'target',snapshot:snapshot,fields:{'certificate_number':'new','issuer':'issuer',
      'issued_at':null,'expires_at':null,'notes':'corrected'});
}

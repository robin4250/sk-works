import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

enum QualificationManagementMode { absent, stopped, enabled, unavailable }

/// Commands are retained briefly by the private server ledger. Only opaque
/// operation/subject IDs are stored on the device; personal photo keys stay intact.
class QualificationRecordManagementRepository {
  QualificationRecordManagementRepository.forTesting({
    required String? Function() actor, required Stream<String?> authChanges,
    required Future<Object?> Function(String, Map<String,dynamic>) rpc,
  }) : _actor=actor, _rpc=rpc, _boundActor=actor() {
    _subscription=authChanges.listen((next){if(next!=_boundActor)_revoked=true;},
      onError:(Object _)=>_revoked=true);
  }
  final String? Function() _actor;
  final Future<Object?> Function(String,Map<String,dynamic>) _rpc;
  final String? _boundActor;
  StreamSubscription<String?>? _subscription;
  static final Set<String> _busyOwners={};
  bool _revoked=false;
  static QualificationRecordManagementRepository? maybeCreate(){
    if(!SupabaseBackend.isInitialized)return null;
    final client=SupabaseBackend.client;
    if(client.auth.currentUser==null)return null;
    return QualificationRecordManagementRepository.forTesting(actor:()=>client.auth.currentUser?.id,
      authChanges:client.auth.onAuthStateChange.map((e)=>e.session?.user.id),
      rpc:(action,data)=>client.rpc('qualification_direct_management',params:{'p_action':action,'p_data':data}));
  }
  void _check(){
    if(_revoked||_boundActor==null||_actor()!=_boundActor){
      throw StateError('ログイン状態が変わりました。画面を開き直してください。');
    }
  }
  Future<void> dispose()async{_revoked=true;await _subscription?.cancel();}
  Future<Object?> _call(String action,Map<String,dynamic> data)async{
    _check();final value=await _rpc(action,data);_check();return value;
  }
  Future<QualificationManagementMode> mode(String companyId)async{
    Object? value;
    try{value=await _call('capability',{'company_id':companyId});}
    on PostgrestException catch(e){
      if(const['PGRST202','42883'].contains(e.code))return QualificationManagementMode.absent;
      rethrow;
    }
    final known=value is Map&&value.length==5&&value['version']==2&&
      value['contract']=='qualification_direct_management'&&value['company_id']==companyId&&
      value['actor_id']==_boundActor&&value['available'] is bool;
    if(!known)return QualificationManagementMode.unavailable;
    return value['available']==true?QualificationManagementMode.enabled:QualificationManagementMode.stopped;
  }
  Future<bool> available(String companyId)async=>await mode(companyId)==QualificationManagementMode.enabled;
  Future<Map<String,dynamic>> inspect(String companyId,String targetId)async{
    if(!await available(companyId))throw StateError('資格情報の管理操作は準備中です。');
    final value=await _call('inspect',{'company_id':companyId,'target_id':targetId});
    if(value is! Map||value['version']!=1||value['contract']!='qualification_direct_management'||
      value['snapshot'] is! Map||value['snapshot']['id']!=targetId||value['snapshot']['company_id']!=companyId){
      throw StateError('資格情報の対象を確認できません。');
    }
    return Map<String,dynamic>.from(value['snapshot'] as Map);
  }
  String _key(String companyId)=>'sko.qualification.management.pending.v2.$_boundActor.$companyId';
  String _legacyKey(String companyId)=>'sko.qualification.management.pending.v1.$_boundActor.$companyId';
  static const _identityKeys={'version','actor_id','company_id','request_id','target_id','operation',
    'worker_id','qualification_master_id'};
  Map<String,dynamic> _identity(Map<String,dynamic> command){
    final snapshot=command['expected_snapshot'];
    return {'version':2,'actor_id':_boundActor,'company_id':command['company_id'],
      'request_id':command['request_id'],'target_id':command['target_id'],'operation':command['operation'],
      'worker_id':command['worker_id']??(snapshot is Map?snapshot['worker_id']:null),
      'qualification_master_id':command['qualification_master_id']??(snapshot is Map?snapshot['qualification_master_id']:null)};
  }
  Map<String,dynamic> _readIdentity(Object? raw,String companyId){
    if(raw is! Map||raw['version']!=2||raw['actor_id']!=_boundActor||raw['company_id']!=companyId||
      raw.keys.any((key)=>!_identityKeys.contains(key))||
      !const['create','update','delete','photos'].contains(raw['operation'])||
      const['request_id','target_id','worker_id','qualification_master_id'].any((k)=>raw[k] is! String||raw[k].isEmpty)){
      throw StateError('保存結果の再確認情報が一致しません。');
    }
    return Map<String,dynamic>.from(raw);
  }
  Future<Map<String,dynamic>?> _legacy(String companyId)async{
    _check();final prefs=await SharedPreferences.getInstance();_check();
    final value=prefs.getString(_legacyKey(companyId));if(value==null)return null;
    final raw=jsonDecode(value);
    if(raw is! Map||raw['version']!=1||raw['actor_id']!=_boundActor||raw['company_id']!=companyId){
      throw StateError('旧形式の未確認操作を確認できません。');
    }
    return Map<String,dynamic>.from(raw);
  }
  Future<Map<String,dynamic>?> pending(String companyId)async{
    _check();final prefs=await SharedPreferences.getInstance();_check();
    final old=await _legacy(companyId);
    if(old!=null)return _readIdentity(_identity(old),companyId);
    final value=prefs.getString(_key(companyId));
    return value==null?null:_readIdentity(jsonDecode(value),companyId);
  }
  Future<void> _writeIdentity(Map<String,dynamic> reference)async{
    final companyId=reference['company_id'] as String;
    _readIdentity(reference,companyId);
    final prefs=await SharedPreferences.getInstance();_check();
    final previous=prefs.getString(_key(companyId));
    if(previous!=null&&_readIdentity(jsonDecode(previous),companyId)['request_id']!=reference['request_id']){
      throw StateError('別の資格操作の保存結果を先に確認してください。');
    }
    if(!await prefs.setString(_key(companyId),jsonEncode(reference)))throw StateError('再確認情報を保存できません。');
    _check();
  }
  Future<void> _clear(Map<String,dynamic> reference)async{
    final prefs=await SharedPreferences.getInstance();_check();
    final companyId=reference['company_id'] as String;
    for(final key in [_key(companyId),_legacyKey(companyId)]){
      final value=prefs.getString(key);if(value==null)continue;
      final raw=jsonDecode(value);
      if(raw is Map&&raw['request_id']==reference['request_id']&&
          !await prefs.remove(key)){
        throw StateError('保存結果は確認済みです。保留表示を再確認してください。');
      }
      _check();
    }
  }
  Map<String,dynamic> _applied(Object? raw,Map<String,dynamic> reference){
    if(raw is! Map||raw['version']!=1||raw['contract']!='qualification_direct_management'||raw['status']!='applied'||
      raw['request_id']!=reference['request_id']||raw['company_id']!=reference['company_id']||
      raw['actor_id']!=_boundActor||raw['target_id']!=reference['target_id']||raw['operation']!=reference['operation']||
      (reference['operation']=='delete'?raw['after']!=null:(raw['after'] is! Map||
       raw['after']['id']!=reference['target_id']||raw['after']['company_id']!=reference['company_id']))){
      throw StateError('同じ資格操作の保存結果を確認できません。');
    }
    return Map<String,dynamic>.from(raw);
  }
  String _pendingStatus(Object? raw,Map<String,dynamic> reference){
    if(raw is! Map||raw['version']!=2||raw['contract']!='qualification_management_pending'||
      const['request_id','company_id','actor_id','target_id','worker_id','qualification_master_id','operation']
        .any((k)=>raw[k]!=reference[k])||!const['prepared','cancelled','expired'].contains(raw['status'])){
      throw StateError('同じ資格操作の準備状態を確認できません。');
    }
    return raw['status'] as String;
  }
  Future<T> _exclusive<T>(String companyId,Future<T> Function() action)async{
    _check();final key='$_boundActor.$companyId';
    if(!_busyOwners.add(key))throw StateError('資格情報の保存処理中です。');
    try{return await action();}finally{_busyOwners.remove(key);}
  }
  Future<Map<String,dynamic>> save({required String companyId,required String operation,
    required String targetId,Map<String,dynamic>? snapshot,Map<String,dynamic>? fields,
    String? workerId,String? masterId})=>_exclusive(companyId,()async{
    if(!await available(companyId))throw StateError('資格情報の管理操作は準備中です。');
    if(await pending(companyId)!=null)throw StateError('先に同じ資格操作の保存結果を再確認してください。');
    if(!const['create','update','delete','photos'].contains(operation)||
      (operation!='create'&&(snapshot?['company_id']!=companyId||snapshot?['id']!=targetId))){
      throw ArgumentError('資格の対象・操作を確認してください。');
    }
    final command=Map<String,dynamic>.from(jsonDecode(jsonEncode({'company_id':companyId,'request_id':_uuid(),
      'target_id':targetId,'operation':operation,'expected_snapshot':snapshot,'fields':fields,
      if(operation=='create')'worker_id':workerId,if(operation=='create')'qualification_master_id':masterId})) as Map);
    final reference=_readIdentity(_identity(command),companyId);
    await _writeIdentity(reference);
    Object? prepared;
    try{prepared=await _call('prepare',command);}
    on PostgrestException catch(e){
      if(const['P0001','42501','22023','40001','23514','55000'].contains(e.code))await _clear(reference);
      rethrow;
    }
    return _afterPrepare(prepared,reference);
  });
  Future<Map<String,dynamic>> create({required String companyId,required String workerId,
    required String masterId,required Map<String,dynamic> fields})=>save(companyId:companyId,
      operation:'create',targetId:_uuid(),workerId:workerId,masterId:masterId,fields:fields);
  Future<Map<String,dynamic>> _afterPrepare(Object? prepared,Map<String,dynamic> reference)async{
    if(prepared is Map&&prepared['status']=='applied'){
      final result=_applied(prepared,reference);await _clear(reference);return result;
    }
    final status=_pendingStatus(prepared,reference);
    if(status!='prepared'){
      await _clear(reference);throw StateError(status=='expired'?'保存準備の期限が切れました。入力し直してください。':'未完了の操作は取り消されています。');
    }
    return _applyId(reference);
  }
  Future<Map<String,dynamic>> _applyId(Map<String,dynamic> reference)async{
    final identity={'company_id':reference['company_id'],'request_id':reference['request_id']};
    Object? result;
    try{result=await _call('apply',identity);}catch(error,stack){
      _check();
      try{result=await _call('get',identity);}catch(_){_check();Error.throwWithStackTrace(error,stack);}
    }
    if(result is Map&&result['status']!='applied'){
      final status=_pendingStatus(result,reference);
      if(status!='prepared')await _clear(reference);
      throw StateError(status=='prepared'?'保存は未完了です。同じ操作を再確認してください。':
        status=='expired'?'保存準備の期限が切れました。入力し直してください。':'未完了の操作は取り消されています。');
    }
    final saved=_applied(result,reference);await _clear(reference);return saved;
  }
  Future<Map<String,dynamic>> recover(String companyId)=>_exclusive(companyId,()async{
    final reference=await pending(companyId);if(reference==null)throw StateError('未確認の資格操作はありません。');
    final old=await _legacy(companyId);
    if(old!=null){
      if(!await available(companyId))throw StateError('旧形式の操作を移行する準備ができていません。');
      final prepared=await _call('prepare',{
        for(final k in ['company_id','request_id','target_id','operation','expected_snapshot','fields','worker_id','qualification_master_id'])
          if(old.containsKey(k))k:old[k]});
      if(prepared is Map&&prepared['status']=='applied'){
        final saved=_applied(prepared,reference);await _clear(reference);return saved;
      }
      final status=_pendingStatus(prepared,reference);
      if(status!='prepared'){await _clear(reference);throw StateError('旧形式の未完了操作は終了しています。入力し直してください。');}
      await _writeIdentity(reference);
      final prefs=await SharedPreferences.getInstance();_check();
      if(!await prefs.remove(_legacyKey(companyId)))throw StateError('移行結果を再確認してください。');
      _check();
    }
    return _applyId(reference);
  });
  Future<Map<String,dynamic>> cancelUncertain(String companyId)=>_exclusive(companyId,()async{
    final reference=await pending(companyId);if(reference==null)throw StateError('未確認の資格操作はありません。');
    final result=await _call('cancel',{for(final k in ['company_id','request_id','target_id','operation','worker_id','qualification_master_id'])k:reference[k]});
    if(result is Map&&result['status']=='applied'){
      final saved=_applied(result,reference);await _clear(reference);return saved;
    }
    final status=_pendingStatus(result,reference);
    if(status=='prepared')throw StateError('取消結果を確認できません。');
    await _clear(reference);return Map<String,dynamic>.from(result as Map);
  });
  String _uuid(){
    final random=Random.secure();final bytes=List<int>.generate(16,(_)=>random.nextInt(256));
    bytes[6]=(bytes[6]&15)|64;bytes[8]=(bytes[8]&63)|128;
    final value=bytes.map((v)=>v.toRadixString(16).padLeft(2,'0')).join();
    return '${value.substring(0,8)}-${value.substring(8,12)}-${value.substring(12,16)}-${value.substring(16,20)}-${value.substring(20)}';
  }
}

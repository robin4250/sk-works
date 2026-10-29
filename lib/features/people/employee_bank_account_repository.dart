import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/supabase_backend.dart';
import '../auth/app_auth_mutation_gateway.dart';
import '../auth/operation_reauthentication_repository.dart';
import '../auth/secondary_reset_session_guard.dart';
import 'own_bank_account_repository.dart';

String employeeBankInitialDigest(String companyId,String workerId,OwnBankAccountInput input) {
  if (!input.isValid) throw StateError('口座情報を確認してください。');
  final values=[companyId.toLowerCase(),workerId.toLowerCase(),input.bankName,input.branchName,
    input.accountType,input.accountNumber,input.accountHolder];
  final canonical='sko-employee-bank-initial-v1\n${values.map((v)=>'${utf8.encode(v).length}:$v').join('\n')}';
  return sha256.convert(utf8.encode(canonical)).toString();
}
class EmployeeBankAccountState {
  const EmployeeBankAccountState({required this.companyId,required this.workerId,
    required this.self,required this.available,required this.managerEnabled,required this.registered,this.updatedAt});
  final String companyId,workerId;
  final bool self,available,managerEnabled;
  final bool? registered;
  final DateTime? updatedAt;
  bool get canRegister=>available && registered==false && (self || managerEnabled);
}
abstract interface class EmployeeBankAccountGateway implements Listenable {
  bool get isCurrent;
  OwnBankAccountGateway? get selfGateway;
  Future<EmployeeBankAccountState> load();
  Future<EmployeeBankAccountState> register(OwnBankAccountInput input,{required Future<String?> Function() requestPassword});
  Future<void> close();
}
/// Selected employee is immutable. No current-worker substitution, direct-table
/// manager write, existing-account update, or missing-capability fallback.
class EmployeeBankAccountRepository extends ChangeNotifier implements EmployeeBankAccountGateway {
  EmployeeBankAccountRepository.forClient(this._client,{required String companyId,required String workerId})
      : companyId=companyId.toLowerCase(),workerId=workerId.toLowerCase() {
    if (!_uuid(this.companyId) || !_uuid(this.workerId)) throw StateError('対象の社員と会社を確認してください。');
    final session=_client.auth.currentSession;
    if (session==null) throw StateError('ログイン状態を確認してください。');
    _session=session;
    _guard=SecondaryResetSessionGuard(currentSession:()=>_client.auth.currentSession,
      changes:_client.auth.onAuthStateChange,onInvalidated:_invalidate);
    _owner=AppAuthMutationGateway.forClient(_client);_admission=_owner.externalFlowAdmission();
    _quarantine=_owner.logoutQuarantine.changes.listen((s){if(s!=AppLogoutQuarantineState.clear)_invalidate();},
      onError:(Object _)=>_invalidate(),onDone:_invalidate);
    var first=true;
    _events=_client.auth.onAuthStateChange.listen((e){
      final replay=first&&identical(e.session,_session);first=false;
      if(!replay)_invalidate();
    },onError:(Object _)=>_invalidate(),onDone:_invalidate);
  }
  static EmployeeBankAccountRepository? maybeCreate({required String companyId,required String workerId}) =>
    SupabaseBackend.isInitialized ? EmployeeBankAccountRepository.forClient(SupabaseBackend.client,companyId:companyId,workerId:workerId) : null;
  final SupabaseClient _client;
  final String companyId,workerId;
  late final Session _session;
  late final SecondaryResetSessionGuard _guard;
  late final AppAuthMutationGateway _owner;
  late final Future<int?> _admission;
  StreamSubscription<AuthState>? _events;
  StreamSubscription<AppLogoutQuarantineState>? _quarantine;
  int? _epoch;
  bool _invalidated=false,_closed=false,_writing=false;
  OwnBankAccountRepository? _self;
  _SelectedOwnBankGateway? _selectedSelf;
  EmployeeBankAccountState? _state;
  static bool _uuid(String v)=>RegExp(r'^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$').hasMatch(v);
  @override bool get isCurrent=>!_closed&&!_invalidated&&_guard.isCurrent&&!_session.isExpired&&_epoch!=null&&_owner.isExternalFlowCurrent(_epoch!);
  @override OwnBankAccountGateway? get selfGateway=>isCurrent&&_state?.self==true ? _selectedSelf : null;
  void _invalidate(){if(_closed||_invalidated)return;_invalidated=true;_state=null;notifyListeners();}
  Future<void> _check() async {
    final epoch=await _admission;_epoch??=epoch;
    if(epoch==null||!_owner.isExternalFlowCurrent(epoch)){_invalidate();throw StateError('ログイン状態が変わりました。');}
    await _guard.checkAfterQueuedEvents();
    if(!isCurrent){_invalidate();throw StateError('ログイン状態が変わりました。');}
  }
  EmployeeBankAccountState _parse(Map<String,dynamic> row,{required bool capability}) {
    final keys=capability?{'protocol','enabled','company_id','worker_id','registered','updated_at'}:{'protocol','company_id','worker_id','registered','updated_at'};
    final updated=row['updated_at']==null?null:DateTime.tryParse(row['updated_at'].toString());
    if(row.length!=keys.length||row.keys.toSet().difference(keys).isNotEmpty||
        row['protocol']!='sko-employee-bank-initial-v1'||row['company_id']!=companyId||row['worker_id']!=workerId||
        row['registered'] is! bool||(capability&&row['enabled'] is! bool)||
        (row['registered']==true&&updated==null)||(row['registered']==false&&row['updated_at']!=null)) {
      throw StateError('対象社員の口座状態を確認できません。');
    }
    return EmployeeBankAccountState(companyId:companyId,workerId:workerId,self:false,available:true,
      managerEnabled:capability?row['enabled']==true:true,registered:row['registered'] as bool,updatedAt:updated);
  }
  @override Future<EmployeeBankAccountState> load() async {
    await _check();
    final member=await _client.from('company_members').select('company_id,user_id')
      .eq('company_id',companyId).eq('user_id',_session.user.id)
      .setHeader('Authorization','Bearer ${_session.accessToken}').maybeSingle().timeout(const Duration(seconds:30));
    await _check();
    if(member==null||member['company_id']!=companyId||member['user_id']!=_session.user.id)throw StateError('対象の会社を確認できません。');
    final worker=await _client.from('workers').select('id,company_id,user_id,status')
      .eq('id',workerId).eq('company_id',companyId).eq('status','active')
      .setHeader('Authorization','Bearer ${_session.accessToken}').maybeSingle().timeout(const Duration(seconds:30));
    await _check();
    if(worker==null||worker['id']!=workerId||worker['company_id']!=companyId||worker['status']!='active')throw StateError('対象の社員を確認できません。');
    if(worker['user_id']==_session.user.id) {
      _self??=OwnBankAccountRepository.forClient(_client,workerId:workerId,companyId:companyId);
      final own=await _self!.load();await _check();
      _selectedSelf??=_SelectedOwnBankGateway(this,_self!);
      return _state=EmployeeBankAccountState(companyId:companyId,workerId:workerId,self:true,available:true,
        managerEnabled:false,registered:own.registered,updatedAt:own.updatedAt);
    }
    dynamic raw;
    try {
      raw=await _client.rpc('employee_bank_initial_capability',params:{'p_company_id':companyId,'p_worker_id':workerId})
        .setHeader('Authorization','Bearer ${_session.accessToken}').timeout(const Duration(seconds:30));
    } on PostgrestException catch(error) {
      await _check();
      if(error.code!='PGRST202'||!error.message.contains('employee_bank_initial_capability'))rethrow;
      return _state=EmployeeBankAccountState(companyId:companyId,workerId:workerId,self:false,available:false,managerEnabled:false,registered:null);
    }
    await _check();
    if(raw is! Map)throw StateError('対象社員の口座状態を確認できません。');
    return _state=_parse(Map<String,dynamic>.from(raw),capability:true);
  }
  @override Future<EmployeeBankAccountState> register(OwnBankAccountInput input,{required Future<String?> Function() requestPassword}) async {
    if(_writing||!input.isValid)throw StateError('口座情報を確認してください。');
    _writing=true;
    try {
      final current=await load();
      if(current.self||!current.canRegister)throw StateError('対象社員の初回登録を利用できません。');
      final target={'company_id':companyId,'worker_id':workerId,'input_sha256':employeeBankInitialDigest(companyId,workerId,input)};
      final password=await requestPassword();await _check();
      if(password==null||password.isEmpty)throw StateError('本人確認をキャンセルしました。');
      final proof=await OperationReauthenticationRepository(_client).requestProof(password:password,operation:'employee.bank.initial',target:target);
      await _check();
      final rechecked=await load();
      if(rechecked.self||!rechecked.canRegister)throw StateError('対象社員の登録状態が変わりました。');
      final raw=await _client.rpc('register_employee_bank_initial',params:{'p_company_id':companyId,'p_worker_id':workerId,
        'p_bank_data':{'bank_name':input.bankName,'branch_name':input.branchName,'account_type':input.accountType,'account_number':input.accountNumber,'account_holder':input.accountHolder},'p_proof':proof})
        .setHeader('Authorization','Bearer ${_session.accessToken}').timeout(const Duration(seconds:30));
      await _check();
      if(raw is! Map)throw StateError('口座の保存結果を確認できません。');
      final saved=_parse(Map<String,dynamic>.from(raw),capability:false);
      if(saved.registered!=true)throw StateError('口座の保存結果を確認できません。');
      return _state=saved;
    } finally {_writing=false;}
  }
  @override Future<void> close() async {
    if(_closed)return;_invalidate();_closed=true;_state=null;
    await _events?.cancel();await _quarantine?.cancel();await _guard.close();await _selectedSelf?.close();await _self?.close();super.dispose();
  }
}

/// Binds the existing self API to this exact selected-employee lifetime too.
class _SelectedOwnBankGateway extends ChangeNotifier implements OwnBankAccountGateway {
  _SelectedOwnBankGateway(this.owner,this.actual) {owner.addListener(_changed);actual.addListener(_changed);}
  final EmployeeBankAccountRepository owner;
  final OwnBankAccountRepository actual;
  bool _closed=false;
  void _changed(){if(!_closed)notifyListeners();}
  @override bool get isCurrent=>!_closed&&owner.isCurrent&&actual.isCurrent;
  @override Future<OwnBankAccountState> load() async {
    final value=await owner.load();
    if(!isCurrent||!value.self||value.registered==null)throw StateError('対象の本人を確認できません。');
    return OwnBankAccountState(registered:value.registered!,updatedAt:value.updatedAt);
  }
  @override Future<OwnBankAccountState> register(OwnBankAccountInput input) async {
    final state=await load();if(state.registered)throw StateError('登録済みの口座情報は保持しました。');
    final saved=await actual.register(input);await owner._check();
    if(!isCurrent)throw StateError('対象の本人を確認できません。');return saved;
  }
  @override Future<void> close() async {if(_closed)return;_closed=true;owner.removeListener(_changed);actual.removeListener(_changed);super.dispose();}
}

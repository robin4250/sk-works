import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/supabase_backend.dart';
import '../../domain/partner_company_bank_account.dart';
import '../auth/app_auth_mutation_gateway.dart';
import '../auth/secondary_reset_session_guard.dart';
import 'people_cloud_repository.dart';

class PartnerCompanyBankWorkspace {
 const PartnerCompanyBankWorkspace({required this.available,required this.version,this.bank});
 final bool available;final int version;final PartnerCompanyBankAccount? bank;
}

class PartnerCompanyBankRepository extends ChangeNotifier {
 PartnerCompanyBankRepository(this._client,{required this.privacySession,required this.expectedCompany,required this.partnerCompanyId}) {
  if(privacySession.company!=expectedCompany || privacySession.actor!=_client.auth.currentUser?.id){throw const PersonnelScopeChanged();}
  final captured=_client.auth.currentSession;
  if(captured==null || captured.isExpired){throw const PersonnelScopeChanged();}
  _token=captured.accessToken;
  _guard=SecondaryResetSessionGuard(currentSession:()=>_client.auth.currentSession,changes:_client.auth.onAuthStateChange,onInvalidated:_invalidate);
  _gateway=AppAuthMutationGateway.forClient(_client);_admission=_gateway.externalFlowAdmission();
  _quarantine=_gateway.logoutQuarantine.changes.listen((state){if(state!=AppLogoutQuarantineState.clear){_invalidate();}},onError:(Object _)=>_invalidate(),onDone:_invalidate);
  var first=true;
  _auth=_client.auth.onAuthStateChange.listen((event){
   final replay=first && identical(event.session,captured) && [AuthChangeEvent.initialSession,AuthChangeEvent.signedIn,AuthChangeEvent.tokenRefreshed].contains(event.event);
   first=false;if(!replay){_invalidate();}
  },onError:(Object _)=>_invalidate(),onDone:_invalidate);
 }
 static PartnerCompanyBankRepository? maybeCreate({required PersonnelPrivacySession privacySession,required String expectedCompany,required String partnerCompanyId})=>
  SupabaseBackend.isInitialized?PartnerCompanyBankRepository(SupabaseBackend.client,privacySession:privacySession,expectedCompany:expectedCompany,partnerCompanyId:partnerCompanyId):null;
 final SupabaseClient _client;
 final PersonnelPrivacySession privacySession;
 final String expectedCompany,partnerCompanyId;
 late final String _token;
 late final SecondaryResetSessionGuard _guard;
 late final AppAuthMutationGateway _gateway;
 late final Future<int?> _admission;
 StreamSubscription<AuthState>? _auth;
 StreamSubscription<AppLogoutQuarantineState>? _quarantine;
 int? _epoch,_privacyEpoch;
 bool _invalid=false,_disposed=false,_writing=false;
 bool get isCurrent=>!_invalid&&!_disposed&&_guard.isCurrent&&_client.auth.currentSession?.accessToken==_token&&_epoch!=null&&_gateway.isExternalFlowCurrent(_epoch!);
 void _invalidate(){if(_invalid||_disposed){return;}_invalid=true;notifyListeners();}
 void _live(){
  if(!isCurrent || _privacyEpoch==null){throw const PersonnelScopeChanged();}
  privacySession.verify(_privacyEpoch!);
  if(privacySession.snapshot?.canManage!=true || privacySession.company!=expectedCompany){throw const PersonnelScopeChanged();}
 }
 Future<void> _check() async {
  final admission=await _admission;_epoch??=admission;
  if(_invalid||_disposed||admission==null||!_gateway.isExternalFlowCurrent(admission)){throw const PersonnelScopeChanged();}
  if(_privacyEpoch!=null){_live();}
  await _guard.checkAfterQueuedEvents();
  await privacySession.read();_privacyEpoch??=privacySession.epoch;_live();
 }
 Future<PartnerCompanyBankWorkspace> load() async {
  await _check();Object? raw;
  try{raw=await _client.rpc('partner_company_bank_read',params:{'p_company':expectedCompany,'p_partner':partnerCompanyId}).setHeader('Authorization','Bearer $_token');}
  on PostgrestException catch(error){if(!const ['PGRST202','42883'].contains(error.code)){rethrow;}_live();return const PartnerCompanyBankWorkspace(available:false,version:0);}
  await _check();
  if(raw is! Map || raw.length!=5 || raw['company_id']!=expectedCompany || raw['partner_company_id']!=partnerCompanyId || raw['available'] is! bool || raw['version'] is! int || raw['version']<0){throw StateError('協力会社の口座登録状態を確認できません。');}
  final bank=raw['bank']==null?null:PartnerCompanyBankAccount.fromJson(raw['bank'],companyId:expectedCompany,partnerCompanyId:partnerCompanyId);
  if((bank==null?0:bank.bankVersion)!=raw['version'] || (raw['available']==false&&(bank!=null||raw['version']!=0))){throw StateError('協力会社の口座保存版を確認できません。');}
  return PartnerCompanyBankWorkspace(available:raw['available'] as bool,version:raw['version'] as int,bank:bank);
 }
 static String _requestId(){final random=Random.secure(),bytes=List.generate(16,(_)=>0);for(var i=0;i<16;i++){bytes[i]=random.nextInt(256);}bytes[6]=(bytes[6]&15)|64;bytes[8]=(bytes[8]&63)|128;final h=bytes.map((v)=>v.toRadixString(16).padLeft(2,'0')).join();return '${h.substring(0,8)}-${h.substring(8,12)}-${h.substring(12,16)}-${h.substring(16,20)}-${h.substring(20)}';}
 Future<PartnerCompanyBankAccount> save({required int expectedVersion,required PartnerCompanyBankAccount bank}) async {
  if(_writing || bank.companyId!=expectedCompany || bank.partnerCompanyId!=partnerCompanyId || bank.bankVersion!=expectedVersion+1){throw StateError('選択した協力会社と保存版を再確認してください。');}
  _writing=true;
  try{
   await _check();
   final raw=await _client.rpc('save_partner_company_bank',params:{'p_company':expectedCompany,'p_partner':partnerCompanyId,'p_expected_version':expectedVersion,'p_request':_requestId(),'p_bank':bank.bankFields}).setHeader('Authorization','Bearer $_token');
   await _check();final result=PartnerCompanyBankAccount.fromJson(raw,companyId:expectedCompany,partnerCompanyId:partnerCompanyId);
   if(result.bankVersion!=bank.bankVersion||!mapEquals(result.bankFields,bank.bankFields)){throw StateError('口座の保存結果を確認できません。再読み込みしてください。');}
   return result;
  }finally{_writing=false;}
 }
 @override void dispose(){if(_disposed){return;}_disposed=true;unawaited(_guard.close().catchError((Object _){}));unawaited((_auth?.cancel()??Future<void>.value()).catchError((Object _){}));unawaited((_quarantine?.cancel()??Future<void>.value()).catchError((Object _){}));super.dispose();}
}

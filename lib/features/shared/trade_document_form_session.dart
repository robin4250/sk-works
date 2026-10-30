import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/app_auth_mutation_gateway.dart';
import '../auth/secondary_reset_session_guard.dart';
import '../auth/sdk_session_replay_baseline.dart';

/// A contract operation belongs to one captured SDK session and gateway epoch.
/// HTTP cancellation is not a promise that an already-started DB TX rolled back.
class TradeDocumentFormSession extends ChangeNotifier with WidgetsBindingObserver {
 TradeDocumentFormSession(this._client,{Object? target,Object? Function()? currentTarget})
  :_target=target,_currentTarget=currentTarget {
  if((target==null)!=(currentTarget==null))throw ArgumentError('Complete target binding required');
  final captured=_client.auth.currentSession;
  if(captured==null||SecondaryResetSessionGuard.identityOf(captured)==null)throw StateError('ログイン状態を確認してください。');
  _captured=captured;
  _token=captured.accessToken;
  _gateway=AppAuthMutationGateway.forClient(_client);_admission=_gateway.externalFlowAdmission();
  _guard=SecondaryResetSessionGuard(currentSession:()=>_client.auth.currentSession,changes:_client.auth.onAuthStateChange,onInvalidated:_invalidate);
  final baseline=SdkSessionReplayBaseline(captured);
  _auth=_client.auth.onAuthStateChange.listen((event){
   final cached=baseline.consume(event,_client.auth.currentSession)&&const [AuthChangeEvent.initialSession,AuthChangeEvent.signedIn,AuthChangeEvent.tokenRefreshed,AuthChangeEvent.userUpdated].contains(event.event);
   if(!cached)_invalidate();
  },onError:(Object _)=>_invalidate(),onDone:_invalidate);
  unawaited(Future<void>.value().then((_)=>baseline.close()));
  _quarantine=_gateway.logoutQuarantine.changes.listen((state){if(state!=AppLogoutQuarantineState.clear)_invalidate();},onError:(Object _)=>_invalidate(),onDone:_invalidate);
  WidgetsBinding.instance.addObserver(this);
  final state=WidgetsBinding.instance.lifecycleState;
  if(const [AppLifecycleState.paused,AppLifecycleState.hidden,AppLifecycleState.detached].contains(state))_invalidate();
 }
 final SupabaseClient _client;
 final Object? _target;
 final Object? Function()? _currentTarget;
 late final Session _captured;
 late final String _token;
 late final SecondaryResetSessionGuard _guard;
 late final AppAuthMutationGateway _gateway;
 late final Future<int?> _admission;
 final _retired=Completer<void>();
 StreamSubscription<AuthState>? _auth;
 StreamSubscription<AppLogoutQuarantineState>? _quarantine;
 int? _epoch;bool _invalid=false,_disposed=false;
 bool belongsTo(SupabaseClient client)=>identical(client,_client);
 bool get _targetCurrent {try{return _currentTarget==null||_currentTarget()==_target;}catch(_){return false;}}
 bool get isCurrent=>!_invalid&&!_disposed&&_epoch!=null&&_targetCurrent&&_guard.isCurrent&&identical(_client.auth.currentSession,_captured)&&_client.auth.currentSession?.accessToken==_token&&_gateway.isExternalFlowCurrent(_epoch!);
 void _invalidate(){if(_invalid||_disposed)return;_invalid=true;if(!_retired.isCompleted)_retired.complete();notifyListeners();}
 void requireScope(){if(!isCurrent){_invalidate();throw StateError('ログイン・会社・書類の状態が変わりました。開き直してください。');}}
 Future<void> ready()async {
  try{
   final admission=await _admission.timeout(const Duration(seconds:10));_epoch??=admission;
   requireScope();await _guard.checkAfterQueuedEvents();requireScope();
  }catch(_){_invalidate();rethrow;}
 }
 Future<Object?> rpc(String action,Map<String,dynamic> params)async {
  await ready();requireScope();
  final request=_client.rpc(action,params:params).setHeader('Authorization','Bearer $_token').abortSignal(_retired.future);
  return _receive(request.then<Object?>((value)=>value));
 }
 Future<Object?> readOwnMemberships()async {
  await ready();requireScope();
  final actor=_client.auth.currentUser!.id;
  return _receive(_client.from('company_members').select('company_id,role')
   .eq('user_id',actor).setHeader('Authorization','Bearer $_token').abortSignal(_retired.future).then<Object?>((v)=>v));
 }
 Future<Object?> readOwnSealCompany(String companyId)async {
  await ready();requireScope();
  return _receive(_client.from('companies').select('id,name,company_seal_enabled,company_seal_style')
   .eq('id',companyId).single().setHeader('Authorization','Bearer $_token').abortSignal(_retired.future).then<Object?>((v)=>v));
 }
 Future<Object?> readPaymentParent({required String id,required String companyId})async {
  await ready();requireScope();
  final request=_client.from('payment_certificates').select('id,company_id,partner_company_id,revision')
   .eq('id',id).eq('company_id',companyId).maybeSingle().setHeader('Authorization','Bearer $_token').abortSignal(_retired.future);
  return _receive(request.then<Object?>((value)=>value));
 }
 Future<Object?> _receive(Future<Object?> request)async {
  requireScope();Object? value;
  try{value=await Future.any<Object?>([
   request,
   _retired.future.then<Object?>((_)=>throw StateError('書類操作の状態が変わりました。開き直してください。')),
  ]).timeout(const Duration(seconds:30));}
  on TimeoutException{_invalidate();throw StateError('書類操作の応答を確認できません。開き直して保存状態を確認してください。');}
  catch(_){requireScope();rethrow;}
  await ready();requireScope();return value;
 }
 @override void didChangeAppLifecycleState(AppLifecycleState state){
  // The host's explicit native-print lease controls inactive. A backgrounded
  // contract is always retired; returning to foreground cannot revive it.
  if(const [AppLifecycleState.paused,AppLifecycleState.hidden,AppLifecycleState.detached].contains(state))_invalidate();
 }
 @override void dispose(){
  if(_disposed)return;_disposed=true;if(!_retired.isCompleted)_retired.complete();WidgetsBinding.instance.removeObserver(this);
  unawaited(_guard.close().catchError((Object _){}));unawaited((_auth?.cancel()??Future<void>.value()).catchError((Object _){}));unawaited((_quarantine?.cancel()??Future<void>.value()).catchError((Object _){}));super.dispose();
 }
}

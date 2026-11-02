import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/supabase_backend.dart';
import '../auth/app_auth_mutation_gateway.dart';
import '../auth/secondary_reset_session_guard.dart';
import 'own_draft_bank_admission.dart';
import 'own_draft_bank_diagnostic.dart';
import 'payroll_statement_repository.dart';

final _uuid=RegExp(r'^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$');
abstract interface class OwnDraftBankGateway implements Listenable {
 bool get isCurrent;
 Future<OwnDraftBankAdmission> read(PayrollStatementRecord statement);
 Future<void> close();
}
class OwnDraftBankRepository extends ChangeNotifier implements OwnDraftBankGateway {
 OwnDraftBankRepository.forClient(this._client) {
  final session=_client.auth.currentSession;
  final identity=SecondaryResetSessionGuard.identityOf(session);
  if(session==null||identity==null)throw StateError('ログイン状態を確認してください。');
  _session=session;_actor=session.user.id;_sid=identity.split('/').last;
  if(!_uuid.hasMatch(_actor)||!_uuid.hasMatch(_sid))throw StateError('ログイン状態を確認してください。');
  _owner=AppAuthMutationGateway.forClient(_client);_admission=_owner.externalFlowAdmission();
  _guard=SecondaryResetSessionGuard(currentSession:()=>_client.auth.currentSession,changes:_client.auth.onAuthStateChange,onInvalidated:_invalidate);
  var first=true,replayOpen=true;
  _events=_client.auth.onAuthStateChange.listen((event){
   final replay=first&&replayOpen&&identical(event.session,_session)&&identical(_client.auth.currentSession,_session)&&
    (event.event==AuthChangeEvent.initialSession||event.event==AuthChangeEvent.signedIn||event.event==AuthChangeEvent.tokenRefreshed);
   first=false;
   if(!replay){_record(OwnDraftBankReadStage.session,OwnDraftBankReadIssue.authenticationEvent);_invalidate();}
  },onError:(Object _){_record(OwnDraftBankReadStage.session,OwnDraftBankReadIssue.authenticationStream);_invalidate();},onDone:(){_record(OwnDraftBankReadStage.session,OwnDraftBankReadIssue.authenticationStream);_invalidate();});
  // Only a queued startup replay is exempt; never leave a live-event observer gap.
  scheduleMicrotask(()=>replayOpen=false);
  _quarantine=_owner.logoutQuarantine.changes.listen((s){if(s!=AppLogoutQuarantineState.clear){_record(OwnDraftBankReadStage.session,OwnDraftBankReadIssue.logoutQuarantine);_invalidate();}},onError:(Object _)=>_invalidate(),onDone:_invalidate);
 }
 static OwnDraftBankRepository? maybeCreate(){if(!SupabaseBackend.isInitialized||SecondaryResetSessionGuard.identityOf(SupabaseBackend.client.auth.currentSession)==null)return null;return OwnDraftBankRepository.forClient(SupabaseBackend.client);}
 final SupabaseClient _client;
 late final Session _session;late final String _actor,_sid;late final AppAuthMutationGateway _owner;late final Future<int?> _admission;late final SecondaryResetSessionGuard _guard;
 StreamSubscription<AuthState>? _events;
 StreamSubscription<AppLogoutQuarantineState>? _quarantine;int? _epoch;bool _closed=false,_retired=false;
 OwnDraftBankDiagnostic? _lastDiagnostic;
 OwnDraftBankDiagnostic? get lastDiagnostic => _lastDiagnostic;
 void _record(OwnDraftBankReadStage stage,OwnDraftBankReadIssue issue){_lastDiagnostic??=OwnDraftBankDiagnostic(stage,issue);}
 Never _fail(OwnDraftBankReadStage stage,OwnDraftBankReadIssue issue){_record(stage,issue);throw OwnDraftBankReadFailure(_lastDiagnostic!);}
 @override bool get isCurrent=>!_closed&&!_retired&&_guard.isCurrent&&!_session.isExpired&&_epoch!=null&&_owner.isExternalFlowCurrent(_epoch!);
 void _invalidate(){if(_closed||_retired)return;_retired=true;notifyListeners();}
 Future<void> _check() async {
  try {_epoch??=await _admission;}catch(_){_invalidate();_fail(OwnDraftBankReadStage.admission,OwnDraftBankReadIssue.admissionRejected);}
  if(_epoch==null||!_owner.isExternalFlowCurrent(_epoch!)){_invalidate();_fail(OwnDraftBankReadStage.admission,OwnDraftBankReadIssue.admissionRejected);}
  try {await _guard.checkAfterQueuedEvents();}catch(_){_invalidate();_fail(OwnDraftBankReadStage.session,OwnDraftBankReadIssue.sessionUnavailable);}
  if(!isCurrent){_invalidate();_fail(OwnDraftBankReadStage.session,OwnDraftBankReadIssue.sessionUnavailable);}
 }
 @override Future<OwnDraftBankAdmission> read(PayrollStatementRecord statement) async {
  if(!_retired)_lastDiagnostic=null;
  await _check();final revision=statement.revision;
  if(!_uuid.hasMatch(statement.id)||!statement.isDraft||!statement.ownDraftBankPurpose||revision==null||revision<0||revision>2147483647)_fail(OwnDraftBankReadStage.statement,OwnDraftBankReadIssue.statementRejected);
  Object? raw;
  try {
   raw=await _client.rpc('personal_payroll_own_draft_bank_v1',params:{'p_statement_id':statement.id,'p_expected_statement_revision':revision,'p_expected_session':_sid}).setHeader('Authorization','Bearer ${_session.accessToken}').timeout(const Duration(seconds:20));
  }on TimeoutException{_fail(OwnDraftBankReadStage.request,OwnDraftBankReadIssue.timeout);}
  on PostgrestException catch(error){
   final issue=error.code=='42501'?OwnDraftBankReadIssue.rpcDenied:
    (error.code=='PGRST202'||error.code=='42883')?OwnDraftBankReadIssue.rpcUnavailable:OwnDraftBankReadIssue.rpcRejected;
   _fail(OwnDraftBankReadStage.request,issue);
  }catch(_){_fail(OwnDraftBankReadStage.request,OwnDraftBankReadIssue.transport);}
  await _check();
  OwnDraftBankAdmission value;
  try {value=OwnDraftBankAdmission.decode(raw,actor:_actor,sid:_sid,statement:statement.id,revision:revision,current:()=>isCurrent);}
  catch(_){_fail(OwnDraftBankReadStage.response,OwnDraftBankReadIssue.invalidResponse);}
  if(value.state==OwnDraftBankState.unavailable)_record(OwnDraftBankReadStage.response,OwnDraftBankReadIssue.basisUnavailable);
  return value;
 }
 @override Future<void> close() async{if(_closed)return;_closed=true;await _quarantine?.cancel();await _events?.cancel();await _guard.close();dispose();}
}

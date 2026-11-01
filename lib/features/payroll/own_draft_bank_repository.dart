import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/supabase_backend.dart';
import '../auth/app_auth_mutation_gateway.dart';
import '../auth/secondary_reset_session_guard.dart';
import 'own_draft_bank_admission.dart';
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
  _events=_client.auth.onAuthStateChange.listen((event){if(event.event!=AuthChangeEvent.initialSession||SecondaryResetSessionGuard.identityOf(event.session)!=identity)_invalidate();},onError:(Object _)=>_invalidate(),onDone:_invalidate);
  _quarantine=_owner.logoutQuarantine.changes.listen((s){if(s!=AppLogoutQuarantineState.clear)_invalidate();},onError:(Object _)=>_invalidate(),onDone:_invalidate);
 }
 static OwnDraftBankRepository? maybeCreate(){if(!SupabaseBackend.isInitialized||SecondaryResetSessionGuard.identityOf(SupabaseBackend.client.auth.currentSession)==null)return null;return OwnDraftBankRepository.forClient(SupabaseBackend.client);}
 final SupabaseClient _client;
 late final Session _session;late final String _actor,_sid;late final AppAuthMutationGateway _owner;late final Future<int?> _admission;late final SecondaryResetSessionGuard _guard;
 StreamSubscription<AuthState>? _events;
 StreamSubscription<AppLogoutQuarantineState>? _quarantine;int? _epoch;bool _closed=false,_retired=false;
 @override bool get isCurrent=>!_closed&&!_retired&&_guard.isCurrent&&!_session.isExpired&&_epoch!=null&&_owner.isExternalFlowCurrent(_epoch!);
 void _invalidate(){if(_closed||_retired)return;_retired=true;notifyListeners();}
 Future<void> _check() async{_epoch??=await _admission;if(_epoch==null||!_owner.isExternalFlowCurrent(_epoch!)){_invalidate();throw StateError('ログイン状態が変わりました。');}await _guard.checkAfterQueuedEvents();if(!isCurrent){_invalidate();throw StateError('ログイン状態が変わりました。');}}
 @override Future<OwnDraftBankAdmission> read(PayrollStatementRecord statement) async {
  await _check();final revision=statement.revision;
  if(!_uuid.hasMatch(statement.id)||!statement.isDraft||!statement.ownDraftBankPurpose||revision==null||revision<0||revision>2147483647)throw StateError('本人の下書き明細を確認してください。');
  final raw=await _client.rpc('personal_payroll_own_draft_bank_v1',params:{'p_statement_id':statement.id,'p_expected_statement_revision':revision,'p_expected_session':_sid}).setHeader('Authorization','Bearer ${_session.accessToken}').timeout(const Duration(seconds:20));
  await _check();
  return OwnDraftBankAdmission.decode(raw,actor:_actor,sid:_sid,statement:statement.id,revision:revision,current:()=>isCurrent);
 }
 @override Future<void> close() async{if(_closed)return;_closed=true;await _quarantine?.cancel();await _events?.cancel();await _guard.close();dispose();}
}

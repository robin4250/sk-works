import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/supabase_backend.dart';
import '../auth/app_auth_mutation_gateway.dart';
import '../auth/secondary_reset_session_guard.dart';
import '../people/own_bank_account_repository.dart';

final _uuid = RegExp(r'^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$');
final _hash = RegExp(r'^[0-9a-f]{64}$');
Never _invalid() => throw const FormatException('個人情報の応答を確認できません。');
bool _revision(Object? v) => v is int && v >= 0 && v <= 9007199254740991;
bool _utcTimestampValid(Object? value) {
 if(value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|\+00:00)$').hasMatch(value))return false;
 final parsed=DateTime.tryParse(value);
 return parsed!=null && parsed.year>=1 && parsed.isUtc && parsed.toIso8601String().substring(0,19)==value.substring(0,19);
}
bool personalBirthDateValid(String? value) {
 if(value==null)return true;
 final date=DateTime.tryParse(value);
 final now=DateTime.now();
 return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) && date!=null &&
  date.year >= 1 && date.toIso8601String().substring(0,10)==value && !date.isAfter(DateTime(now.year,now.month,now.day));
}
Map<String,dynamic> personalBankJson(OwnBankAccountInput input) {
 if(!input.isValid)_invalid();
 return {'bank_name':input.bankName,'branch_name':input.branchName,'account_type':input.accountType,
  'account_number':input.accountNumber,'account_holder':input.accountHolder};
}
OwnBankAccountInput? _bank(Object? raw) {
 if(raw==null)return null;
 if(raw is! Map || raw.keys.toSet().difference({'bank_name','branch_name','account_type','account_number','account_holder'}).isNotEmpty || raw.length!=5 || raw.values.any((v)=>v is! String))_invalid();
 final value=OwnBankAccountInput(bankName:raw['bank_name'],branchName:raw['branch_name'],accountType:raw['account_type'],accountNumber:raw['account_number'],accountHolder:raw['account_holder']);
 if(!value.isValid || jsonEncode(personalBankJson(value))!=jsonEncode({for(final key in personalBankJson(value).keys)key:raw[key]}))_invalid();
 return value;
}
class PersonalDetailsSummary {
 const PersonalDetailsSummary({required this.revision,required this.exists,required this.bankRegistered,this.birthDate});
 final int revision;final bool exists,bankRegistered;final String? birthDate;
}
typedef PersonalProof = Future<String?> Function(String operation,Map<String,dynamic> target);
abstract interface class PersonalDetailsGateway implements Listenable {
 String get actorId;
 bool get isCurrent;
 bool get pendingUnknown;
 Future<PersonalDetailsSummary> load();
 Future<OwnBankAccountInput?> readBank(int revision,PersonalProof proof);
 Future<bool> save(int revision,Map<String,dynamic> changes,String operation,PersonalProof proof);
 Future<bool> reconcile();
 Future<void> close();
}
class PersonalDetailsUnconfirmed implements Exception {
 const PersonalDetailsUnconfirmed();
 @override String toString()=>'保存結果を確認できません。再送せず「保存結果を確認」を選んでください。';
}
/// Metadata only. Bank values, date, password and proof are never persisted here.
abstract interface class PersonalDetailsPendingStore {
 Future<Map<String,dynamic>?> read(String actor);
 Future<void> put(String actor,Map<String,dynamic> metadata);
 Future<void> clear(String actor);
}
class _PreferencesPending implements PersonalDetailsPendingStore {
 String key(String actor)=>'sko.personal_details.pending.v1.$actor';
 @override Future<Map<String,dynamic>?> read(String actor) async {
  final preferences=await SharedPreferences.getInstance();
  // Web preferences are cached per Dart context. Observe externally written
  // ambiguity metadata before deciding whether another save may be prepared.
  // This refresh is visibility only; it does not provide cross-tab exclusion.
  if(kIsWeb)await preferences.reload();
  final raw=preferences.getString(key(actor));
  if(raw==null)return null;
  final value=jsonDecode(raw);if(value is! Map<String,dynamic>)_invalid();return value;
 }
 @override Future<void> put(String actor,Map<String,dynamic> metadata) async {
  if(!await (await SharedPreferences.getInstance()).setString(key(actor),jsonEncode(metadata)))throw const PersonalDetailsUnconfirmed();
 }
 @override Future<void> clear(String actor) async {
  if(!await (await SharedPreferences.getInstance()).remove(key(actor)))throw const PersonalDetailsUnconfirmed();
 }
}
class PersonalDetailsRepository extends ChangeNotifier implements PersonalDetailsGateway {
 PersonalDetailsRepository.forClient(this._client,{PersonalDetailsPendingStore? pendingStore}) : _store=pendingStore??_PreferencesPending() {
  final session=_client.auth.currentSession;
  final identity=SecondaryResetSessionGuard.identityOf(session);
  if(session==null||identity==null)_invalid();
  _session=session;actorId=session.user.id;_sid=identity.split('/').last;
  if(!_uuid.hasMatch(actorId)||!_uuid.hasMatch(_sid))_invalid();
  _owner=AppAuthMutationGateway.forClient(_client);_admission=_owner.externalFlowAdmission();
  _guard=SecondaryResetSessionGuard(currentSession:()=>_client.auth.currentSession,
   changes:_client.auth.onAuthStateChange,onInvalidated:_invalidate);
  _quarantine=_owner.logoutQuarantine.changes.listen((s){if(s!=AppLogoutQuarantineState.clear)_invalidate();},onError:(Object _)=>_invalidate(),onDone:_invalidate);
 }
 static PersonalDetailsRepository? maybeCreate(){
  if(!SupabaseBackend.isInitialized || SecondaryResetSessionGuard.identityOf(SupabaseBackend.client.auth.currentSession)==null)return null;
  return PersonalDetailsRepository.forClient(SupabaseBackend.client);
 }
 final SupabaseClient _client;final PersonalDetailsPendingStore _store;
 late final Session _session;late final String _sid;@override late final String actorId;
 late final AppAuthMutationGateway _owner;late final Future<int?> _admission;late final SecondaryResetSessionGuard _guard;
 StreamSubscription<AppLogoutQuarantineState>? _quarantine;
 static final _activeWrites=<String>{};
 int? _epoch;bool _closed=false,_retired=false,_writing=false;Map<String,dynamic>? _pending;
 @override bool get pendingUnknown=>_pending!=null;
 @override bool get isCurrent=>!_closed&&!_retired&&_guard.isCurrent&&_session.isExpired==false&&_epoch!=null&&_owner.isExternalFlowCurrent(_epoch!);
 void _invalidate(){if(_closed||_retired)return;_retired=true;notifyListeners();}
 Future<void> _check() async {
  _epoch??=await _admission;
  if(_epoch==null||!_owner.isExternalFlowCurrent(_epoch!)){_invalidate();throw StateError('ログイン状態を確認してください。');}
  await _guard.checkAfterQueuedEvents();if(!isCurrent){_invalidate();throw StateError('ログイン状態を確認してください。');}
 }
 Future<Map<String,dynamic>> _rpc(String name,Map<String,dynamic> args,Set<String> keys) async {
  await _check();final raw=await _client.rpc(name,params:{'p_expected_session':_sid,...args})
   .setHeader('Authorization','Bearer ${_session.accessToken}').timeout(const Duration(seconds:20));
  await _check();
  if(raw is! Map || raw.length!=keys.length || raw.keys.any((k)=>!keys.contains(k)) ||
   raw['protocol_version'] is! int || raw['protocol_version']!=1 || raw['actor_id']!=actorId || raw['session_id']!=_sid || !_revision(raw['revision'])){_invalid();}
  return Map<String,dynamic>.from(raw);
 }
 static const _base={'protocol_version','actor_id','session_id','revision'};
 void _pendingShape(Map<String,dynamic> p) {
  if(p.keys.toSet().difference({'actor','sid','before','operation','digest'}).isNotEmpty || p.length!=5 || p['actor']!=actorId || p['sid'] is! String || !_uuid.hasMatch(p['sid']) || !_revision(p['before']) || p['operation'] is! String || !_uuid.hasMatch(p['operation']) || p['digest'] is! String || !_hash.hasMatch(p['digest']))_invalid();
 }
 @override Future<PersonalDetailsSummary> load() async {
  await _check();final stored=await _store.read(actorId);await _check();
  if(stored!=null){_pendingShape(stored);_pending=Map.unmodifiable(stored);}
  final r=await _rpc('personal_details_summary_v1',{}, {..._base,'record_exists','birth_date','bank_registered','updated_at'});
  if(r['record_exists'] is! bool || r['bank_registered'] is! bool || r['birth_date']!=null&&r['birth_date'] is! String || !personalBirthDateValid(r['birth_date']))_invalid();
  if(r['record_exists']==false && (r['revision']!=0||r['birth_date']!=null||r['bank_registered']!=false||r['updated_at']!=null))_invalid();
  if(r['record_exists']==true && (r['revision']==0||!_utcTimestampValid(r['updated_at'])))_invalid();
  return PersonalDetailsSummary(revision:r['revision'],exists:r['record_exists'],bankRegistered:r['bank_registered'],birthDate:r['birth_date']);
 }
 @override Future<OwnBankAccountInput?> readBank(int revision,PersonalProof proof) async {
  await _check();final token=await proof('personal.bank.read',{'user_id':actorId,'revision':revision});await _check();
  if(token==null)return null;
  if(!_hash.hasMatch(token))_invalid();
  final r=await _rpc('personal_bank_read_v1',{'p_expected_revision':revision,'p_proof':token},{..._base,'bank_account'});
  if(r['revision']!=revision)_invalid();return _bank(r['bank_account']);
 }
 @override Future<bool> save(int revision,Map<String,dynamic> changes,String operation,PersonalProof proof) async {
  await _check();
  if(_writing||_pending!=null||!_revision(revision)||!_uuid.hasMatch(operation)||changes.isEmpty||changes.keys.any((k)=>!{'birth_date','bank_account'}.contains(k)))throw StateError('保存条件を確認してください。');
  if(changes.containsKey('birth_date') && (changes['birth_date']!=null&&changes['birth_date'] is! String || !personalBirthDateValid(changes['birth_date'])))_invalid();
  if(changes.containsKey('bank_account'))_bank(changes['bank_account']);
  // Freeze the exact normalized payload before password/async turns.
  final frozen=Map<String,dynamic>.unmodifiable(jsonDecode(jsonEncode(changes)));
  if (!_activeWrites.add(actorId)) throw StateError('別の保存処理を確認してください。');
  _writing=true;
  try {
   final stored=await _store.read(actorId);await _check();
   if(stored!=null){_pendingShape(stored);_pending=Map.unmodifiable(stored);throw const PersonalDetailsUnconfirmed();}
   final prepared=await _rpc('personal_details_prepare_save_v1',{'p_expected_revision':revision,'p_operation_id':operation,'p_changes':frozen},{..._base,'operation_id','input_sha256'});
   final digest=prepared['input_sha256'];if(prepared['revision']!=revision||prepared['operation_id']!=operation||digest is! String||!_hash.hasMatch(digest))_invalid();
   final token=await proof('personal.details.save',{'user_id':actorId,'before_revision':revision,'operation_id':operation,'input_sha256':digest});await _check();
   if(token==null)return false;
   if(!_hash.hasMatch(token))_invalid();
   final pending={'actor':actorId,'sid':_sid,'before':revision,'operation':operation,'digest':digest};
   _pending=Map.unmodifiable(pending);
   // Persist ambiguity fence BEFORE dispatch. Failure never dispatches a write.
   await _store.put(actorId,pending);await _check();
   try {
    final result=await _rpc('personal_details_save_v1',{'p_expected_revision':revision,'p_operation_id':operation,'p_changes':frozen,'p_input_sha256':digest,'p_proof':token},{..._base,'operation_id','input_sha256','outcome'});
    if(result['revision']!=revision+1||result['operation_id']!=operation||result['input_sha256']!=digest||result['outcome']!='applied')_invalid();
    await _store.clear(actorId);await _check();_pending=null;return true;
   } catch (_) {throw const PersonalDetailsUnconfirmed();}
  } finally {_writing=false;_activeWrites.remove(actorId);}
 }
 @override Future<bool> reconcile() async {
  await _check();final p=_pending;if(p==null)return false;
  _pendingShape(p);if(p['sid']!=_sid)throw const PersonalDetailsUnconfirmed();
  final r=await _rpc('personal_details_reconcile_v1',{'p_before_revision':p['before'],'p_operation_id':p['operation'],'p_input_sha256':p['digest']},{..._base,'operation_id','input_sha256','outcome'});
  if(r['operation_id']!=p['operation']||r['input_sha256']!=p['digest']||!{'applied','unknown'}.contains(r['outcome']))_invalid();
  if(r['outcome']=='unknown')return false;
  if(r['revision']!=p['before']+1)_invalid();
  await _store.clear(actorId);await _check();_pending=null;return true;
 }
 @override Future<void> close() async {if(_closed)return;_closed=true;await _quarantine?.cancel();await _guard.close();dispose();}
}

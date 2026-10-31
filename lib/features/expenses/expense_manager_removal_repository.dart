import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/supabase_backend.dart';
import 'expense_management_repository.dart';

bool _uuid(Object? value) => value is String && RegExp(r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$').hasMatch(value);

class ExpenseRemovalCapability {
  ExpenseRemovalCapability(Map<String, dynamic> data, String? session) {
    if(data.containsKey('manager_removal_version') && data['manager_removal_version'] is! int) throw const FormatException('Invalid capability version');
    for (final key in ['manager_removal_enabled', 'can_manager_remove']) {
      if (data.containsKey(key) && data[key] is! bool) throw const FormatException('Invalid deletion capability');
    }
    enabled = data['manager_removal_version'] == 1 && data['manager_removal_enabled'] == true &&
      data['can_manager_remove'] == true && _uuid(session) && data['manager_removal_session'] == session;
  }
  late final bool enabled;
}

class ExpenseRemovalCommand {
  ExpenseRemovalCommand(this.id, this.actor, this.company, this.claim, this.revision, this.session, this.reason);
  factory ExpenseRemovalCommand.create(String actor, String company, String claim, int revision, String session, String reason) {
    final bytes = List.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64; bytes[8] = (bytes[8] & 63) | 128;
    final h = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return ExpenseRemovalCommand('${h.substring(0,8)}-${h.substring(8,12)}-${h.substring(12,16)}-${h.substring(16,20)}-${h.substring(20)}',actor,company,claim,revision,session,reason);
  }
  final String id, actor, company, claim, session, reason;
  final int revision;
  Map<String,dynamic> get params => {'p_command':id,'p_company':company,'p_claim':claim,'p_revision':revision,'p_session':session,'p_reason':reason};
  String get encoded => jsonEncode({'actor':actor,...params});
  factory ExpenseRemovalCommand.decode(String value) {
    final raw = jsonDecode(value);
    if (raw is! Map || raw.length != 7) throw const FormatException('Invalid deletion journal');
    final v = Map<String,dynamic>.from(raw);
    for(final key in ['actor','p_command','p_company','p_claim','p_session']) {
      if (!_uuid(v[key])) throw const FormatException('Invalid deletion identity');
    }
    if(v['p_revision'] is! int || v['p_revision'] < 1 || v['p_reason'] is! String || v['p_reason'].trim()!=v['p_reason'] || v['p_reason'].length>1000) throw const FormatException('Invalid deletion payload');
    return ExpenseRemovalCommand(v['p_command'],v['actor'],v['p_company'],v['p_claim'],v['p_revision'],v['p_session'],v['p_reason']);
  }
}

class ExpenseRemovalResult {
  ExpenseRemovalResult(Map<String,dynamic> value, ExpenseRemovalCommand command) {
    const keys={'command_id','company_id','claim_id','requested_revision','manager_deleted','deleted_by','deleted_at','financial_state','correction_required','notification_id','notification_state'};
    if(value.length!=keys.length || !value.keys.toSet().containsAll(keys)) { throw const FormatException('Unexpected deletion result fields'); }
    if(value['command_id']!=command.id || value['company_id']!=command.company || value['claim_id']!=command.claim ||
      value['requested_revision'] is! int || value['requested_revision']!=command.revision || value['deleted_by']!=command.actor || value['manager_deleted']!=true ||
      value['notification_state']!='stored' || !_uuid(value['notification_id']) ||
      value['deleted_at'] is! String || DateTime.tryParse(value['deleted_at'])==null ||
      value['correction_required'] is! bool ||
      !['withdrawn_unfinalized','finalized_original_retained'].contains(value['financial_state']) ||
      value['correction_required']!=(value['financial_state']=='finalized_original_retained')) { throw const FormatException('Deletion result unavailable'); }
    correctionRequired = value['correction_required'];
  }
  late final bool correctionRequired;
}

abstract interface class ExpenseRemovalJournal {
  Future<String?> read(String key);
  Future<void> write(String key,String value);
  Future<void> erase(String key,String expected);
}
class SharedExpenseRemovalJournal implements ExpenseRemovalJournal {
  @override Future<String?> read(String key)async{final prefs=await SharedPreferences.getInstance();await prefs.reload();return prefs.getString(key);}
  @override Future<void> write(String key,String value)async{
    final prefs=await SharedPreferences.getInstance();
    if(!await prefs.setString(key,value))throw StateError('削除確認を端末に保存できません。');
    await prefs.reload();if(prefs.getString(key)!=value)throw StateError('削除確認の保存内容を確認できません。');
  }
  @override Future<void> erase(String key,String expected)async{
    final prefs=await SharedPreferences.getInstance();await prefs.reload();
    if(prefs.getString(key)!=expected || !await prefs.remove(key))throw StateError('保存済みの結果を再確認してください。');
    await prefs.reload();if(prefs.getString(key)!=null)throw StateError('結果確認の保存状態を確認できません。');
  }
}

/// A pending command is observation-only after an uncertain send. Never resend
/// from a new login, or infer success from a missing result.
class ExpenseManagerRemovalRepository {
  ExpenseManagerRemovalRepository({String? Function()? actor, String? Function()? session, ExpenseRpc? rpc, Stream<void>? invalidations, ExpenseRemovalJournal? journal})
    : _actor=actor??(() => SupabaseBackend.isInitialized ? SupabaseBackend.client.auth.currentUser?.id : null),
      _session=session??_liveSession,
      _rpc=rpc??((name,params)=>SupabaseBackend.client.rpc(name,params:params)),
      _journal=journal??SharedExpenseRemovalJournal() {
    final events=invalidations ?? (SupabaseBackend.isInitialized ? SupabaseBackend.client.auth.onAuthStateChange.where((event)=>event.event!=AuthChangeEvent.initialSession).map((_) {}) : null);
    _trackingHealthy=events!=null;
    _subscription=events?.listen((_) {_invalidate();},onError:(Object _){_retireTracking();},onDone:_retireTracking);
  }
  final ExpenseRemovalJournal _journal;
  StreamSubscription<void>? _subscription;
  final _changes=StreamController<void>.broadcast(sync:true);
  Stream<void> get changes=>_changes.stream;
  int get epoch=>_epoch;
  void _retireTracking(){_trackingHealthy=false;_invalidate();}
  void _invalidate(){_epoch++;if(!_changes.isClosed)_changes.add(null);}
  late bool _trackingHealthy;
  int _epoch=0;
  bool _disposed=false;
  void dispose(){if(_disposed)return;_disposed=true;_epoch++;_subscription?.cancel();_changes.close();}
  void _same(int epoch,String expected,String? capturedSession){
    if(!_trackingHealthy || _disposed || _epoch!=epoch || actor!=expected || session!=capturedSession)throw StateError('ログイン状態が変わりました。保存結果を照会してください。');
  }
  final String? Function() _actor, _session;
  final ExpenseRpc _rpc;
  String? get actor=>_actor();
  String? get session=>_session();
  static String? _liveSession() {
    try { final token=SupabaseBackend.client.auth.currentSession?.accessToken;
      if(token==null)return null;
      final body=jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(token.split('.')[1]))));
      return body is Map && _uuid(body['session_id']) ? body['session_id'] as String : null;
    }catch(_){return null;}
  }
  String _key(String actor,String company)=>'sko.expense.manager-removal.v1.$actor.$company';
  void _check(String expected){if(!_trackingHealthy || _disposed || actor!=expected || !_uuid(session))throw StateError('ログイン情報が変わりました。');}
  Future<ExpenseRemovalCommand?> pending(String company)async{
    final expected=actor;if(expected==null)throw StateError('ログインが必要です。');
    final epoch=_epoch;final capturedSession=session;
    final text=await _journal.read(_key(expected,company));_same(epoch,expected,capturedSession);if(text==null)return null;
    final command=ExpenseRemovalCommand.decode(text);
    if(command.actor!=expected || command.company!=company)throw StateError('削除の対象が一致しません。');return command;
  }
  static final _running=<String>{};
  Future<ExpenseRemovalResult> submit(ExpenseRemovalCommand command,ExpenseRemovalCapability capability)async{
    ExpenseRemovalCommand.decode(command.encoded);_check(command.actor);
    if(!capability.enabled || session!=command.session)throw StateError('削除機能と現在の権限を確認してください。');
    final epoch=_epoch;final capturedSession=session;
    final key=_key(command.actor,command.company);
    if(!_running.add(key))throw StateError('削除結果を確認中です。');
    try{
      final previous=await _journal.read(key);_same(epoch,command.actor,capturedSession);
      if(previous!=null)throw StateError('先に保存済みの削除結果を確認してください。');
      if(session!=command.session)throw StateError('ログイン情報が変わりました。');
      await _journal.write(key,command.encoded);_same(epoch,command.actor,capturedSession);
      if(await _journal.read(key)!=command.encoded)throw StateError('削除確認の保存内容を確認できません。');
      _same(epoch,command.actor,capturedSession);_check(command.actor);if(session!=command.session)throw StateError('ログイン情報が変わりました。');
      final raw=await _rpc('expense_manager_remove',command.params);_same(epoch,command.actor,capturedSession);_check(command.actor);
      if(session!=command.session)throw StateError('ログイン情報が変わりました。保存結果を照会してください。');
      final result=ExpenseRemovalResult(Map<String,dynamic>.from(raw as Map),command);
      await _clear(key,command,epoch,capturedSession);return result;
    }finally{_running.remove(key);}
  }
  Future<ExpenseRemovalResult?> observe(ExpenseRemovalCommand command)async{
    ExpenseRemovalCommand.decode(command.encoded);_check(command.actor);
    final epoch=_epoch;final capturedSession=session;
    final key=_key(command.actor,command.company);
    if(!_running.add(key))throw StateError('削除結果を確認中です。');
    try{
      final previous=await _journal.read(key);_same(epoch,command.actor,capturedSession);_check(command.actor);
      if(previous!=command.encoded)throw StateError('保存済みの削除対象が一致しません。');
      final observedSession=session;
      final raw=await _rpc('expense_manager_removal_result',{'p_command':command.id,'p_company':command.company});_same(epoch,command.actor,capturedSession);_check(command.actor);
      if(session!=observedSession)throw StateError('ログイン情報が変わりました。');
      if(raw==null)return null;
      final result=ExpenseRemovalResult(Map<String,dynamic>.from(raw as Map),command);
      await _clear(key,command,epoch,capturedSession);return result;
    }finally{_running.remove(key);}
  }
  Future<void> _clear(String key,ExpenseRemovalCommand command,int epoch,String? capturedSession)async{
    _same(epoch,command.actor,capturedSession);_check(command.actor);
    await _journal.erase(key,command.encoded);
    try{_same(epoch,command.actor,capturedSession);_check(command.actor);}
    catch(_){if(await _journal.read(key)==null)await _journal.write(key,command.encoded);rethrow;}
  }
}

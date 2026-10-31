import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/supabase_backend.dart';
import 'expense_management_repository.dart';

bool _uuid(Object? value) => value is String && RegExp(r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$').hasMatch(value);

class ExpenseRemovalCapability {
  ExpenseRemovalCapability(Map<String, dynamic> data, String? session) {
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
    if(value['command_id']!=command.id || value['company_id']!=command.company || value['claim_id']!=command.claim ||
      value['requested_revision']!=command.revision || value['deleted_by']!=command.actor || value['manager_deleted']!=true ||
      value['notification_state']!='stored' || !_uuid(value['notification_id']) ||
      value['deleted_at'] is! String || DateTime.tryParse(value['deleted_at'])==null ||
      value['correction_required'] is! bool ||
      !['withdrawn_unfinalized','finalized_original_retained'].contains(value['financial_state']) ||
      value['correction_required']!=(value['financial_state']=='finalized_original_retained')) throw const FormatException('Deletion result unavailable');
    correctionRequired = value['correction_required'];
  }
  late final bool correctionRequired;
}

/// A pending command is observation-only after an uncertain send. Never resend
/// from a new login, or infer success from a missing result.
class ExpenseManagerRemovalRepository {
  ExpenseManagerRemovalRepository({String? Function()? actor, String? Function()? session, ExpenseRpc? rpc})
    : _actor=actor??(() => SupabaseBackend.isInitialized ? SupabaseBackend.client.auth.currentUser?.id : null),
      _session=session??_liveSession,
      _rpc=rpc??((name,params)=>SupabaseBackend.client.rpc(name,params:params));
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
  void _check(String expected){if(actor!=expected || !_uuid(session))throw StateError('ログイン情報が変わりました。');}
  Future<ExpenseRemovalCommand?> pending(String company)async{
    final expected=actor;if(expected==null)throw StateError('ログインが必要です。');
    final prefs=await SharedPreferences.getInstance();if(actor!=expected)throw StateError('ログイン情報が変わりました。');
    final text=prefs.getString(_key(expected,company));if(text==null)return null;
    final command=ExpenseRemovalCommand.decode(text);
    if(command.actor!=expected || command.company!=company)throw StateError('削除の対象が一致しません。');return command;
  }
  static final _running=<String>{};
  Future<ExpenseRemovalResult> submit(ExpenseRemovalCommand command,ExpenseRemovalCapability capability)async{
    ExpenseRemovalCommand.decode(command.encoded);_check(command.actor);
    if(!capability.enabled || session!=command.session)throw StateError('削除機能と現在の権限を確認してください。');
    final key=_key(command.actor,command.company);
    if(!_running.add(key))throw StateError('削除結果を確認中です。');
    try{
      final prefs=await SharedPreferences.getInstance();_check(command.actor);
      if(prefs.containsKey(key))throw StateError('先に保存済みの削除結果を確認してください。');
      if(session!=command.session)throw StateError('ログイン情報が変わりました。');
      if(!await prefs.setString(key,command.encoded))throw StateError('削除確認を端末に保存できません。');
      _check(command.actor);if(session!=command.session)throw StateError('ログイン情報が変わりました。');
      final raw=await _rpc('expense_manager_remove',command.params);_check(command.actor);
      if(session!=command.session)throw StateError('ログイン情報が変わりました。保存結果を照会してください。');
      final result=ExpenseRemovalResult(Map<String,dynamic>.from(raw as Map),command);
      await _clear(prefs,key,command);return result;
    }finally{_running.remove(key);}
  }
  Future<ExpenseRemovalResult?> observe(ExpenseRemovalCommand command)async{
    ExpenseRemovalCommand.decode(command.encoded);_check(command.actor);
    final key=_key(command.actor,command.company);
    if(!_running.add(key))throw StateError('削除結果を確認中です。');
    try{
      final prefs=await SharedPreferences.getInstance();_check(command.actor);
      if(prefs.getString(key)!=command.encoded)throw StateError('保存済みの削除対象が一致しません。');
      final observedSession=session;
      final raw=await _rpc('expense_manager_removal_result',{'p_command':command.id,'p_company':command.company});_check(command.actor);
      if(session!=observedSession)throw StateError('ログイン情報が変わりました。');
      if(raw==null)return null;
      final result=ExpenseRemovalResult(Map<String,dynamic>.from(raw as Map),command);
      await _clear(prefs,key,command);return result;
    }finally{_running.remove(key);}
  }
  Future<void> _clear(SharedPreferences prefs,String key,ExpenseRemovalCommand command)async{
    _check(command.actor);
    if(prefs.getString(key)!=command.encoded || !await prefs.remove(key))throw StateError('保存済みの結果を再確認してください。');
    _check(command.actor);
  }
}

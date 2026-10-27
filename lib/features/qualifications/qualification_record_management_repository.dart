import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

enum QualificationManagementMode { absent, stopped, enabled, unavailable }

/// Management operations are immediate, audited and independent of the personal
/// photo approval queue. Unknown capability always disables new operations.
class QualificationRecordManagementRepository {
  QualificationRecordManagementRepository.forTesting({
    required String? Function() actor,
    required Stream<String?> authChanges,
    required Future<Object?> Function(String, Map<String, dynamic>) rpc,
  }) : _actor = actor, _rpc = rpc, _boundActor = actor() {
    _subscription = authChanges.listen((next) {
      if (next != _boundActor) _revoked = true;
    }, onError: (Object _) => _revoked = true);
  }
  final String? Function() _actor;
  final Future<Object?> Function(String, Map<String, dynamic>) _rpc;
  final String? _boundActor;
  StreamSubscription<String?>? _subscription;
  bool _revoked = false;
  bool _busy = false;

  static QualificationRecordManagementRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return QualificationRecordManagementRepository.forTesting(
      actor: () => client.auth.currentUser?.id,
      authChanges: client.auth.onAuthStateChange.map((e) => e.session?.user.id),
      rpc: (action, data) => client.rpc('qualification_direct_management',
        params: {'p_action': action, 'p_data': data}),
    );
  }

  void _check() {
    if (_revoked || _boundActor == null || _actor() != _boundActor) {
      throw StateError('ログイン状態が変わりました。画面を開き直してください。');
    }
  }
  Future<void> dispose() async { _revoked = true; await _subscription?.cancel(); }

  Future<Object?> _call(String action, Map<String, dynamic> data) async {
    _check(); final value = await _rpc(action, data); _check(); return value;
  }

  Future<QualificationManagementMode> mode(String companyId) async {
    Object? value;
    try { value = await _call('capability', {'company_id': companyId}); }
    on PostgrestException catch (error) {
      if (const ['PGRST202','42883'].contains(error.code)) return QualificationManagementMode.absent;
      rethrow;
    }
    final known = value is Map && value.length == 5 && value['version'] == 1 &&
      value['contract'] == 'qualification_direct_management' &&
      value['company_id'] == companyId && value['actor_id'] == _boundActor && value['available'] is bool;
    if (!known) return QualificationManagementMode.unavailable;
    return (value as Map)['available'] == true ? QualificationManagementMode.enabled : QualificationManagementMode.stopped;
  }

  Future<bool> available(String companyId) async => await mode(companyId) == QualificationManagementMode.enabled;

  Future<Map<String,dynamic>> inspect(String companyId, String targetId) async {
    if (!await available(companyId)) throw StateError('資格情報の管理操作は準備中です。');
    final value = await _call('inspect', {'company_id': companyId, 'target_id': targetId});
    if (value is! Map || value['version'] != 1 || value['contract'] != 'qualification_direct_management' ||
        value['snapshot'] is! Map || value['snapshot']['id'] != targetId ||
        value['snapshot']['company_id'] != companyId) {
      throw StateError('資格情報の対象を確認できません。');
    }
    return Map<String,dynamic>.from(value['snapshot'] as Map);
  }

  String _key(String companyId) => 'sko.qualification.management.pending.v1.$_boundActor.$companyId';
  Future<Map<String,dynamic>?> pending(String companyId) async {
    _check(); final prefs = await SharedPreferences.getInstance(); _check();
    final value = prefs.getString(_key(companyId));
    if (value == null) return null;
    final raw = jsonDecode(value);
    if (raw is! Map || raw['version'] != 1 || raw['actor_id'] != _boundActor ||
        raw['company_id'] != companyId || raw['request_id'] is! String || raw['target_id'] is! String ||
        !const ['create','update','delete','photos'].contains(raw['operation'])) {
      throw StateError('保存結果の再確認情報が一致しません。');
    }
    return Map<String,dynamic>.from(raw);
  }

  Future<void> _write(Map<String,dynamic> command) async {
    _check(); final prefs = await SharedPreferences.getInstance(); _check();
    if (!await prefs.setString(_key(command['company_id'] as String), jsonEncode(command))) {
      throw StateError('再確認用の情報を保存できません。');
    }
    _check();
  }
  Future<void> _clear(String companyId) async {
    final prefs = await SharedPreferences.getInstance(); _check();
    if (!await prefs.remove(_key(companyId))) throw StateError('保存済みです。保留表示を再確認してください。');
    _check();
  }

  Map<String,dynamic> _result(Object? raw, Map<String,dynamic> command) {
    if (raw is! Map || raw['version'] != 1 || raw['contract'] != 'qualification_direct_management' ||
        raw['status'] != 'applied' || raw['request_id'] != command['request_id'] ||
        raw['company_id'] != command['company_id'] || raw['actor_id'] != _boundActor ||
        raw['target_id'] != command['target_id'] || raw['operation'] != command['operation'] ||
        (command['operation'] == 'delete' ? raw['after'] != null :
          (raw['after'] is! Map || raw['after']['id'] != command['target_id'] || raw['after']['company_id'] != command['company_id']))) {
      throw StateError('同じ資格操作の保存結果を確認できません。');
    }
    return Map<String,dynamic>.from(raw);
  }

  Future<T> _exclusive<T>(Future<T> Function() action) async {
    if (_busy) throw StateError('資格情報の保存処理中です。');
    _busy = true;
    try { return await action(); } finally { _busy = false; }
  }

  Future<Map<String,dynamic>> save({required String companyId,
    required String operation, required String targetId,
    Map<String,dynamic>? snapshot, Map<String,dynamic>? fields,
    String? workerId, String? masterId,
  }) => _exclusive(() async {
    if (!await available(companyId)) throw StateError('資格情報の管理操作は準備中です。');
    if (await pending(companyId) != null) throw StateError('先に同じ資格操作の保存結果を再確認してください。');
    if (!const ['create','update','delete','photos'].contains(operation) ||
        (operation != 'create' && (snapshot?['company_id'] != companyId || snapshot?['id'] != targetId))) {
      throw ArgumentError('資格の対象・操作を確認してください。');
    }
    final command = <String,dynamic>{'version':1,'actor_id':_boundActor,
      'company_id':companyId,'request_id':_uuid(),'target_id':targetId,'operation':operation,
      'expected_snapshot':snapshot,'fields':fields,
      if (operation == 'create') 'worker_id':workerId,
      if (operation == 'create') 'qualification_master_id':masterId};
    await _write(command);
    return _applySame(command, firstAttempt:true);
  });

  Future<Map<String,dynamic>> create({required String companyId,
    required String workerId, required String masterId, required Map<String,dynamic> fields,
  }) => save(companyId:companyId, operation:'create', targetId:_uuid(),
    workerId:workerId, masterId:masterId, fields:fields);

  Future<Map<String,dynamic>> recover(String companyId) => _exclusive(() async {
    final command = await pending(companyId);
    if (command == null) throw StateError('未確認の資格操作はありません。');
    return _applySame(command);
  });

  Future<Map<String,dynamic>> _applySame(Map<String,dynamic> command, {bool firstAttempt = false}) async {
    Object? value;
    try {
      value = await _call('apply', {
        for (final key in ['company_id','request_id','target_id','operation','expected_snapshot','fields','worker_id','qualification_master_id'])
          if (command.containsKey(key)) key:command[key],
      });
    } catch (error, stack) {
      _check();
      try {
        value = await _call('get', {'company_id':command['company_id'],'request_id':command['request_id']});
      } catch (_) {
        _check();
        // A definite first-transaction rejection cannot have committed this ID.
        if (firstAttempt && error is PostgrestException &&
            const ['P0001','42501','22023','40001','23514','55000'].contains(error.code)) {
          await _clear(command['company_id'] as String);
        }
        Error.throwWithStackTrace(error, stack);
      }
    }
    final saved = _result(value, command);
    await _clear(command['company_id'] as String);
    return saved;
  }

  String _uuid() {
    final r = Random.secure(); final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6]=(b[6]&15)|64;b[8]=(b[8]&63)|128;
    final s=b.map((v)=>v.toRadixString(16).padLeft(2,'0')).join();
    return '${s.substring(0,8)}-${s.substring(8,12)}-${s.substring(12,16)}-${s.substring(16,20)}-${s.substring(20)}';
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import '../auth/secondary_reset_session_guard.dart';

class OwnBankAccountInput {
  OwnBankAccountInput({required String bankName, required String branchName,
    required this.accountType, required String accountNumber, required String accountHolder})
      : bankName = bankName.trim(), branchName = branchName.trim(),
        accountNumber = String.fromCharCodes(accountNumber.trim().runes.map(
          (c) => c >= 0xff10 && c <= 0xff19 ? c - 0xfee0 : c)),
        accountHolder = accountHolder.trim();
  final String bankName, branchName, accountType, accountNumber, accountHolder;
  bool get isValid => [bankName, branchName, accountHolder]
    .every((v) => v.isNotEmpty && v.runes.length <= 100) &&
    const ['普通','当座','貯蓄'].contains(accountType) &&
    RegExp(r'^[0-9]{7}$').hasMatch(accountNumber);
}

class OwnBankAccountState {
  const OwnBankAccountState({required this.registered, this.updatedAt});
  final bool registered;
  final DateTime? updatedAt;
}

abstract interface class OwnBankAccountGateway implements Listenable {
  bool get isCurrent;
  Future<OwnBankAccountState> load();
  Future<OwnBankAccountState> register(OwnBankAccountInput input);
  Future<void> close();
}

/// Uses only the existing self-scoped table/RLS and status-sync trigger. It
/// never reads account contents or updates, deletes, or upserts an existing row.
class OwnBankAccountRepository extends ChangeNotifier implements OwnBankAccountGateway {
  OwnBankAccountRepository.forClient(this._client, {required this.workerId, required this.companyId}) {
    if (!_uuid(workerId) || !_uuid(companyId)) throw StateError('本人と会社の情報を確認してください。');
    _session = _client.auth.currentSession;
    _actor = _session?.user.id;
    _guard = SecondaryResetSessionGuard(currentSession: () => _client.auth.currentSession,
      changes: _client.auth.onAuthStateChange, onInvalidated: _invalidate);
    var first = true;
    _events = _client.auth.onAuthStateChange.listen((event) {
      final replay = first && identical(event.session, _session);
      first = false;
      if (event.event == AuthChangeEvent.signedIn && !replay) _invalidate();
    }, onError: (Object _) => _invalidate(), onDone: _invalidate);
  }
  static OwnBankAccountRepository? maybeCreate({required String workerId, required String companyId}) {
    if (!SupabaseBackend.isInitialized) return null;
    return OwnBankAccountRepository.forClient(SupabaseBackend.client, workerId:workerId, companyId:companyId);
  }
  final SupabaseClient _client;
  final String workerId, companyId;
  late final Session? _session;
  late final String? _actor;
  late final SecondaryResetSessionGuard _guard;
  StreamSubscription<AuthState>? _events;
  bool _invalidated = false, _closed = false, _writing = false;
  static bool _uuid(String v) => RegExp(r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$').hasMatch(v);
  static const _metadata = 'worker_id,company_id,updated_at';
  @override
  bool get isCurrent => !_closed && !_invalidated && _guard.isCurrent && _session?.isExpired == false;
  void _invalidate() {
    if (_closed || _invalidated) return;
    _invalidated = true; notifyListeners();
  }
  Future<void> _check() async {
    await _guard.checkAfterQueuedEvents();
    if (!isCurrent) { _invalidate(); throw StateError('ログイン状態が変わりました。画面を開き直してください。'); }
  }
  Future<void> _ownScope() async {
    await _check();
    final member = await _client.from('company_members').select('company_id,user_id')
      .eq('company_id',companyId).eq('user_id',_actor!)
      .setHeader('Authorization','Bearer ${_session!.accessToken}').maybeSingle()
      .timeout(const Duration(seconds:30));
    await _check();
    if (member == null || member['company_id'] != companyId || member['user_id'] != _actor) {
      throw StateError('所属会社を確認できません。');
    }
    final worker = await _client.from('workers').select('id,company_id,user_id')
      .eq('id',workerId).eq('company_id',companyId).eq('user_id',_actor).eq('status','active')
      .setHeader('Authorization','Bearer ${_session.accessToken}').maybeSingle()
      .timeout(const Duration(seconds:30));
    await _check();
    if (worker == null || worker['id'] != workerId || worker['company_id'] != companyId || worker['user_id'] != _actor) {
      throw StateError('ログイン中の本人の情報を確認できません。');
    }
  }
  OwnBankAccountState _state(Map<String,dynamic>? row) {
    if (row == null) return const OwnBankAccountState(registered:false);
    final updated = DateTime.tryParse(row['updated_at']?.toString() ?? '');
    if (row['worker_id'] != workerId || row['company_id'] != companyId || updated == null ||
        row.keys.toSet().difference({'worker_id','company_id','updated_at'}).isNotEmpty) {
      throw StateError('口座の登録状態を確認できません。');
    }
    return OwnBankAccountState(registered:true,updatedAt:updated);
  }
  @override
  Future<OwnBankAccountState> load() async {
    await _ownScope();
    final row = await _client.from('worker_private_bank_accounts').select(_metadata)
      .eq('worker_id',workerId).eq('company_id',companyId)
      .setHeader('Authorization','Bearer ${_session!.accessToken}').maybeSingle()
      .timeout(const Duration(seconds:30));
    await _check();
    return _state(row);
  }
  @override
  Future<OwnBankAccountState> register(OwnBankAccountInput input) async {
    if (_writing || !input.isValid) throw StateError('銀行名・支店名・口座名義と7桁の口座番号を確認してください。');
    _writing = true;
    try {
      if ((await load()).registered) throw StateError('登録済みの口座情報は保持しました。');
      await _check();
      final row = await _client.from('worker_private_bank_accounts').insert({
        'worker_id':workerId,'company_id':companyId,'bank_name':input.bankName,
        'branch_name':input.branchName,'account_type':input.accountType,
        'account_number':input.accountNumber,'account_holder':input.accountHolder,
      }).select(_metadata).setHeader('Authorization','Bearer ${_session!.accessToken}').single()
        .timeout(const Duration(seconds:30));
      await _check();
      return _state(row);
    } finally { _writing = false; }
  }
  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true; await _events?.cancel(); await _guard.close(); super.dispose();
  }
}

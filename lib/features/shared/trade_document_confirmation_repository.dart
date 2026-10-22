import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/supabase_backend.dart';
import 'trade_document_confirmation_model.dart';

abstract interface class TradeConfirmationRepository {
  String? get actorId;
  String? get sessionKey;
  Stream<String?> get sessionChanges;
  Future<bool> available();
  Future<TradeConfirmationWorkspace> workspace(String kind, String parentId, String revision);
  Future<Map<String, dynamic>> resolve(String kind, String parentId);
  Future<TradeConfirmationPreview> preview(TradeConfirmationWorkspace workspace);
  Future<TradeConfirmationResult> confirm(TradeConfirmationCommand command);
  Future<TradeConfirmationResult?> receipt(TradeConfirmationCommand command);
  Future<Map<String, dynamic>> render(Map<String, dynamic> scope, {bool archive = false});
  Future<Map<String, dynamic>> received(String tradeCompanyId);
  Future<Map<String, dynamic>> receive(String tradeCompanyId, String documentId, int revision);
}

class SupabaseTradeConfirmationRepository implements TradeConfirmationRepository {
  SupabaseTradeConfirmationRepository(this._client)
      : _actor = _client.auth.currentUser?.id, _token = _client.auth.currentSession?.accessToken {
    _subscription = _client.auth.onAuthStateChange.listen((event) {
      if (event.session?.user.id != _actor || event.session?.accessToken != _token) _revoked = true;
    }, onError: (Object _) => _revoked = true);
  }
  final SupabaseClient _client;
  final String? _actor, _token;
  bool _revoked = false, _verified = false;
  StreamSubscription<AuthState>? _subscription;
  static SupabaseTradeConfirmationRepository? maybeCreate() =>
    SupabaseBackend.isInitialized && SupabaseBackend.client.auth.currentSession != null
      ? SupabaseTradeConfirmationRepository(SupabaseBackend.client) : null;
  @override String? get actorId => _client.auth.currentUser?.id;
  @override String? get sessionKey => _client.auth.currentSession?.accessToken;
  @override Stream<String?> get sessionChanges => _client.auth.onAuthStateChange.map((e) => e.session?.accessToken);
  void verify() {
    if (_revoked || _actor == null || _token == null || actorId != _actor || sessionKey != _token) {
      throw StateError('ログイン情報が変わりました。書類を開き直してください。');
    }
  }
  Future<Object?> _call(String name, Map<String, dynamic> params, {bool probe = false}) async {
    verify();
    if (!probe && !_verified) throw StateError('書類の確認機能を再確認してください。');
    final result = await _client.rpc(name, params: params).setHeader('Authorization', 'Bearer $_token');
    verify();
    return result;
  }
  @override Future<bool> available() async {
    _verified = false;
    try {
      final value = await _call('trade_document_confirmation_contract_version', {}, probe: true);
      if (value is int && value == 1) { _verified = true; return true; }
      if (value is int && value == 0) return false;
      throw const FormatException('書類の確認機能の対応状況を確認できません');
    } on PostgrestException catch (error) {
      verify();
      // Only an absent version RPC establishes an older deployment. Transport,
      // permission and malformed replies must never bypass combined approval.
      if (error.code == 'PGRST202' || error.code == '42883') return false;
      rethrow;
    }
  }
  @override Future<TradeConfirmationWorkspace> workspace(String kind, String parentId, String revision) async =>
    TradeConfirmationWorkspace.parse(await _call('trade_document_confirmation_workspace', {
      'p_kind': kind, 'p_parent_id': parentId, 'p_source_revision': revision}),
      kind: kind, parentId: parentId, sourceRevision: revision, actorId: _actor!);
  @override Future<Map<String, dynamic>> resolve(String kind, String parentId) async {
    final raw = await _call('resolve_trade_document_confirmation', {'p_kind': kind, 'p_parent_id': parentId});
    if (raw is! Map || raw['contract_version'] is! int || raw['contract_version'] != 1 || raw['actor_id'] != _actor ||
        raw['kind'] != kind || raw['parent_id'] != parentId || !tradeConfirmationUuid(raw['company_id']) ||
        raw['side'] != 'issued' || raw['can_render_current'] is! bool || raw['can_render_archive'] is! bool ||
        !const {'approved', 'open', 'unavailable'}.contains(raw['phase'])) {
      throw const FormatException('保存済み書類の確認状態が一致しません');
    }
    return tradeConfirmationCopy(raw) as Map<String, dynamic>;
  }
  @override Future<TradeConfirmationPreview> preview(TradeConfirmationWorkspace workspace) async =>
    TradeConfirmationPreview.parse(await _call('preview_trade_document_confirmation', workspace.scope), workspace);
  @override Future<TradeConfirmationResult> confirm(TradeConfirmationCommand command) async =>
    TradeConfirmationResult.parse(await _call('confirm_trade_document_with_seal', command.params), command);
  @override Future<TradeConfirmationResult?> receipt(TradeConfirmationCommand command) async {
    final raw = await _call('read_trade_document_confirmation_receipt', command.receiptParams);
    if (raw is! Map || raw['contract_version'] is! int || raw['contract_version'] != 1 || raw['found'] is! bool) {
      throw const FormatException('書類の確認結果を読み取れません');
    }
    return raw['found'] == true ? TradeConfirmationResult.parse(raw['result'], command) : null;
  }
  @override Future<Map<String, dynamic>> render(Map<String, dynamic> scope, {bool archive = false}) async {
    const keys = {'p_company_id', 'p_local_document_id', 'p_document_revision', 'p_kind', 'expected_document_id'};
    if (scope.length != keys.length || !keys.every(scope.containsKey) || !tradeConfirmationUuid(scope['expected_document_id'])) {
      throw const FormatException('承認済み書類の対象を確認してください');
    }
    final args = {for (final key in keys.where((key) => key != 'expected_document_id')) key: scope[key], 'p_archive': archive};
    final raw = await _call('render_confirmed_trade_document', args);
    if (raw is! Map) throw const FormatException('承認済み書類を取得できません');
    return tradeConfirmationCopy(raw) as Map<String, dynamic>;
  }
  @override Future<Map<String, dynamic>> received(String tradeCompanyId) async {
    final raw = await _call('list_received_trade_document_confirmations', {'p_trade_company_id': tradeCompanyId});
    if (raw is! Map || raw['contract_version'] is! int || raw['contract_version'] != 1 || raw['actor_id'] != _actor ||
        raw['trade_company_id'] != tradeCompanyId || !tradeConfirmationUuid(raw['company_id']) ||
        !tradeConfirmationUuid(raw['peer_company_id']) || raw['items'] is! List || (raw['items'] as List).length > 200) {
      throw const FormatException('受領した書類の一覧を確認できません');
    }
    return tradeConfirmationCopy(raw) as Map<String, dynamic>;
  }
  @override Future<Map<String, dynamic>> receive(String tradeCompanyId, String documentId, int revision) async {
    final raw = await _call('received_trade_document_confirmation_workspace', {'p_trade_company_id': tradeCompanyId,
      'p_document_id': documentId, 'p_document_revision': revision});
    if (raw is! Map || raw['contract_version'] is! int || raw['contract_version'] != 1 || raw['actor_id'] != _actor || raw['side'] != 'received' ||
        raw['document_id'] != documentId || raw['document_revision'] != revision ||
        !tradeConfirmationUuid(raw['company_id']) || !tradeConfirmationUuid(raw['local_document_id']) ||
        raw['local_document_id'] == documentId || !const {'invoice', 'payment_certificate'}.contains(raw['kind']) ||
        raw['phase'] != 'approved' || raw['can_render'] != true || raw['can_render_current'] is! bool ||
        raw['can_render_archive'] != true || raw['source_changed'] is! bool) {
      throw const FormatException('受領した書類の対象が一致しません');
    }
    return tradeConfirmationCopy(raw) as Map<String, dynamic>;
  }
  Future<void> dispose() async { _revoked = true; await _subscription?.cancel(); }
}

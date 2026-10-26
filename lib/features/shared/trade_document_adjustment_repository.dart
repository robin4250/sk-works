import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'trade_document_adjustment_model.dart';

/// Pins this page to the opening actor/session. Server RPCs remain responsible
/// for current membership, document locks, calculation and ledger authorization.
class SupabaseTradeDocumentAdjustmentRepository implements TradeDocumentAdjustmentPort {
  SupabaseTradeDocumentAdjustmentRepository(this._client)
      : _actor = _client.auth.currentUser?.id,
        _token = _client.auth.currentSession?.accessToken {
    _auth = _client.auth.onAuthStateChange.listen((event) {
      if (event.session?.user.id != _actor || event.session?.accessToken != _token || !_same) {
        invalidate();
      }
    }, onError: (_) => invalidate(), onDone: invalidate);
  }
  final SupabaseClient _client;
  final String? _actor, _token;
  StreamSubscription<dynamic>? _auth;
  bool _revoked = false;
  Future<void>? _disposing;
  bool get _same => !_revoked && _actor != null && _token != null &&
    _client.auth.currentUser?.id == _actor &&
    _client.auth.currentSession?.accessToken == _token &&
    _client.auth.currentSession?.isExpired == false;
  void invalidate() { _revoked = true; }
  void _verify() {
    if (!_same) { invalidate(); throw StateError('ログイン状態が変わりました。画面を開き直してください。'); }
  }
  Future<Object?> _rpc(String name, Map<String, dynamic> params) async {
    _verify();
    try {
      final raw = await _client.rpc(name, params: params)
        .setHeader('Authorization', 'Bearer $_token');
      _verify();
      return raw;
    } on PostgrestException catch (error) {
      _verify();
      // Only explicit server rejection is known not to have committed. Network,
      // malformed and unexpected responses remain uncertain; never retry writes.
      if (const {'42501', 'P0001', '40001', '23505', '22023', 'PGRST202', '42883'}.contains(error.code)) {
        throw const TradeDocumentAdjustmentRejected('登録条件を確認できません。最新の状態を確認してください。');
      }
      throw StateError('通信結果を確認できません。');
    } catch (_) {
      _verify();
      throw StateError('通信結果を確認できません。');
    }
  }

  @override
  Future<TradeDocumentAdjustmentWorkspace> load({required String companyId,
    required TradeDocumentAdjustmentKind kind, required String month, String? partyId}) async {
    final company = tradeDocumentAdjustmentUuid(companyId);
    final period = tradeDocumentAdjustmentMonth(month);
    final party = partyId == null ? null : tradeDocumentAdjustmentUuid(partyId);
    final data = _map(await _rpc('read_trade_document_adjustments', {
      'p_company_id': company, 'p_kind': kind.value, 'p_month': period, 'p_party_id': party}));
    if (_string(data, 'company_id') != company || _string(data, 'kind') != kind.value ||
        _string(data, 'month') != period || _nullableString(data, 'party_id') != party) { _invalid(); }
    return TradeDocumentAdjustmentWorkspace(companyId: company, kind: kind, month: period, partyId: party,
      parties: _list(data, 'parties').map((value) {
        final row = _map(value);
        return TradeDocumentAdjustmentParty(id: _string(row, 'id'), companyId: _string(row, 'company_id'),
          kind: _kind(_string(row, 'kind')), name: _string(row, 'name'));
      }).toList(),
      entries: _list(data, 'entries').map((value) {
        final row = _map(value);
        return TradeDocumentAdjustmentEntry(id: _string(row, 'id'), title: _string(row, 'title'),
          amountYen: _integer(row, 'amount_yen'), sign: _sign(_string(row, 'sign')),
          recurrence: _recurrence(_string(row, 'recurrence')), editable: _boolean(row, 'editable'),
          calculationMode: _mode(_string(row, 'calculation_mode')),
          templateVersion: _nullableInteger(row, 'template_version'), siteId: _nullableString(row, 'site_id'),
          canStop: _boolean(row, 'can_stop'), canceled: _boolean(row, 'canceled'),
          templateStopped: _boolean(row, 'template_stopped'), version: _integer(row, 'version'));
      }).toList(),
      version: _integer(data, 'version'), ready: _boolean(data, 'ready'), canEdit: _boolean(data, 'can_edit'),
      taxMode: _string(data, 'tax_mode'), locked: _boolean(data, 'locked'),
      supportedModes: _list(data, 'supported_modes').map((value) {
        if (value is! String) { _invalid(); } return _mode(value);
      }).toSet(),
      chargeSites: _list(data, 'charge_sites').map((value) {
        final row = _map(value);
        return TradeDocumentAdjustmentChargeSite(id: _string(row, 'id'), label: _string(row, 'label'));
      }).toList());
  }

  @override
  Future<TradeDocumentAdjustmentPreview> preview(TradeDocumentAdjustmentCommand command) async {
    final data = _map(await _rpc('preview_trade_document_adjustment', {'p_command': command.toJson()}));
    final preview = TradeDocumentAdjustmentPreview(request: _map(data['request']), token: _string(data, 'token'),
      baseTotalYen: _integer(data, 'base_total_yen'), resultTotalYen: _integer(data, 'result_total_yen'),
      welfareYen: _nullableInteger(data, 'welfare_yen'), taxYen: _nullableInteger(data, 'tax_yen'),
      adjustmentYen: _nullableInteger(data, 'adjustment_yen'));
    preview.verify(command);
    return preview;
  }

  @override
  Future<TradeDocumentAdjustmentReceipt> apply(TradeDocumentAdjustmentCommand command,
      {required TradeDocumentAdjustmentPreview preview}) async {
    preview.verify(command);
    final receipt = _receipt(await _rpc('apply_trade_document_adjustment', {
      'p_command': command.toJson(), 'p_preview_token': preview.token}));
    receipt.verify(command, preview);
    return receipt;
  }

  @override
  Future<TradeDocumentAdjustmentReceipt?> lookup(TradeDocumentAdjustmentCommand command) async {
    final data = await _rpc('lookup_trade_document_adjustment', {
      'p_company_id': command.companyId, 'p_command_id': command.commandId});
    if (data == null) { return null; }
    final receipt = _receipt(data);
    // Compare complete immutable request without inventing a saved preview.
    TradeDocumentAdjustmentPreview(request: receipt.request, token: 'lookup',
      baseTotalYen: 0, resultTotalYen: receipt.resultTotalYen).verify(command);
    return receipt;
  }

  @override
  Future<TradeDocumentAdjustmentHistory> history({required String companyId,
      required TradeDocumentAdjustmentKind kind, required String partyId, required String month, int? beforeId}) async {
    final company = tradeDocumentAdjustmentUuid(companyId), party = tradeDocumentAdjustmentUuid(partyId);
    final period = tradeDocumentAdjustmentMonth(month);
    if (beforeId != null && (beforeId < 1 || beforeId > 9007199254740991)) { _invalid(); }
    final data = _map(await _rpc('read_trade_document_adjustment_history', {
      'p_company_id': company, 'p_kind': kind.value, 'p_party_id': party,
      'p_month': period, 'p_before_id': beforeId}));
    final history = TradeDocumentAdjustmentHistory(companyId: _string(data, 'company_id'),
      kind: _kind(_string(data, 'kind')), partyId: _string(data, 'party_id'), month: _string(data, 'month'),
      entries: _list(data, 'entries').map((value) {
        final row = _map(value);
        final sign = _nullableString(row, 'sign'), recurrence = _nullableString(row, 'recurrence');
        final mode = _nullableString(row, 'calculation_mode'), timestamp = _string(row, 'created_at');
        if (!RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(timestamp)) { _invalid(); }
        final createdAt = DateTime.tryParse(timestamp);
        if (createdAt == null) { _invalid(); }
        return TradeDocumentAdjustmentHistoryEntry(id: _integer(row, 'id'), commandId: _string(row, 'command_id'),
          actorId: _string(row, 'actor_id'), createdAt: createdAt,
          action: TradeDocumentAdjustmentAction.values.firstWhere((action) => action.name == _string(row, 'action'), orElse: _invalid),
          title: _string(row, 'title'), sign: sign == null ? null : _sign(sign),
          amountYen: _nullableInteger(row, 'amount_yen'), recurrence: recurrence == null ? null : _recurrence(recurrence),
          calculationMode: mode == null ? null : _mode(mode), beforeTotalYen: _integer(row, 'before_total_yen'),
          afterTotalYen: _integer(row, 'after_total_yen'), changedMonths: _list(row, 'changed_months').map((month) {
            if (month is! String) { _invalid(); } return tradeDocumentAdjustmentMonth(month);
          }).toList());
      }).toList(), hasMore: _boolean(data, 'has_more'));
    history.verify(companyId: company, kind: kind, partyId: party, month: period, beforeId: beforeId);
    return history;
  }

  TradeDocumentAdjustmentReceipt _receipt(Object? value) {
    final data = _map(value);
    return TradeDocumentAdjustmentReceipt(request: _map(data['request']), applied: _boolean(data, 'applied'),
      version: _integer(data, 'version'), entryId: _string(data, 'entry_id'),
      previewToken: _string(data, 'preview_token'), resultTotalYen: _integer(data, 'result_total_yen'));
  }
  Future<void> dispose() { invalidate(); return _disposing ??= _close(); }
  Future<void> _close() async { await _auth?.cancel(); }
}

Never _invalid() => throw const FormatException('取得した登録内容を確認できません。');
Map<String, dynamic> _map(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) { _invalid(); }
  return Map<String, dynamic>.from(value);
}
String _string(Map<String, dynamic> data, String key) {
  final value = data[key]; if (value is! String) { _invalid(); } return value;
}
String? _nullableString(Map<String, dynamic> data, String key) {
  final value = data[key]; if (value == null) { return null; }
  if (value is! String) { _invalid(); } return value;
}
int _integer(Map<String, dynamic> data, String key) {
  final value = data[key]; if (value is! int) { _invalid(); } return value;
}
int? _nullableInteger(Map<String, dynamic> data, String key) {
  final value = data[key]; if (value == null) { return null; }
  if (value is! int) { _invalid(); } return value;
}
bool _boolean(Map<String, dynamic> data, String key) {
  final value = data[key]; if (value is! bool) { _invalid(); } return value;
}
List<dynamic> _list(Map<String, dynamic> data, String key) {
  final value = data[key]; if (value is! List) { _invalid(); } return List<dynamic>.from(value);
}
TradeDocumentAdjustmentKind _kind(String value) => TradeDocumentAdjustmentKind.values.firstWhere(
  (kind) => kind.value == value, orElse: _invalid);
TradeDocumentAdjustmentSign _sign(String value) => TradeDocumentAdjustmentSign.values.firstWhere(
  (sign) => sign.value == value, orElse: _invalid);
TradeDocumentAdjustmentRecurrence _recurrence(String value) => TradeDocumentAdjustmentRecurrence.values.firstWhere(
  (recurrence) => recurrence.value == value, orElse: _invalid);
TradeDocumentAdjustmentCalculationMode _mode(String value) => TradeDocumentAdjustmentCalculationMode.values.firstWhere(
  (mode) => mode.value == value, orElse: _invalid);

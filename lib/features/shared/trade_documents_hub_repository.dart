import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import '../auth/secondary_reset_session_guard.dart';
import 'trade_document_form_session.dart';
import 'trade_documents_hub_contract.dart';

class TradeDocumentsHubSnapshot {
  const TradeDocumentsHubSnapshot({required this.companyId, required this.role,
    required this.availability, required this.parties});
  final String companyId, role;
  final TradeDocumentsHubAvailability availability;
  final List<TradeDocumentsHubParty> parties;
}

/// This repository never writes company, payroll, order or master settings.
/// All reads use the existing session/gateway boundary and captured token.
class TradeDocumentsHubRepository extends ChangeNotifier {
  TradeDocumentsHubRepository(this._client)
    : _session = TradeDocumentFormSession(_client),
      _actor = _client.auth.currentUser?.id,
      _identity = SecondaryResetSessionGuard.identityOf(_client.auth.currentSession) {
    _session.addListener(_changed);
  }
  static TradeDocumentsHubRepository? maybeCreate() => SupabaseBackend.isInitialized &&
    SupabaseBackend.client.auth.currentSession != null
      ? TradeDocumentsHubRepository(SupabaseBackend.client) : null;
  final SupabaseClient _client;
  final TradeDocumentFormSession _session;
  final String? _actor, _identity;
  String? _company;
  bool _closed = false;
  TradeDocumentsHubSnapshot? _snapshot;
  TradeDocumentsHubSnapshot? get snapshot => _snapshot;
  void _changed() { if (!_closed) { notifyListeners(); } }
  void requireCurrent() {
    if (_closed || _actor == null || _identity == null ||
        _client.auth.currentUser?.id != _actor ||
        SecondaryResetSessionGuard.identityOf(_client.auth.currentSession) != _identity) {
      throw StateError('注文・請書を開き直してください。');
    }
    _session.requireScope();
  }

  Future<TradeDocumentsHubSnapshot> load() async {
    try { return await _load(); }
    catch (_) {
      _snapshot = null;
      if (!_closed) { notifyListeners(); }
      rethrow;
    }
  }
  Future<TradeDocumentsHubSnapshot> _load() async {
    await _session.ready(); requireCurrent();
    final rows = await _session.readOwnMemberships(); requireCurrent();
    if (rows is! List || rows.length != 1 || rows.single is! Map ||
        !const {'owner', 'admin', 'manager'}.contains(rows.single['role']) ||
        rows.single['company_id'] is! String ||
        (rows.single['company_id'] as String).isEmpty) {
      throw StateError('管理者・サブ管理者の会社を一意に確認できません。');
    }
    final company = rows.single['company_id'] as String;
    final role = rows.single['role'] as String;
    if (_company != null && _company != company) {
      throw StateError('会社の状態が変わりました。開き直してください。');
    }
    _company = company;
    final rawFlags = await _session.rpc('current_master_feature_flags', {});
    requireCurrent();
    if (rawFlags is! Map) { throw StateError('機能設定を確認できません。'); }
    final availability = TradeDocumentsHubAvailability.fromFlags(
      Map<String, dynamic>.from(rawFlags));
    final parties = <TradeDocumentsHubParty>[];
    if (availability.enabled) {
      // Deliberately no fallback to owner-only profile reads or permissive
      // client role checks. An absent server contract leaves this unavailable.
      final access = await _session.rpc('standalone_trade_document_access', {});
      requireCurrent();
      final actor = _actor!;
      TradeDocumentsHubAccess.fromJson(access, actorId: actor, companyId: company,
        sessionId: _identity!.substring(actor.length + 1), role: role);
      final directory = await _session.rpc('trade_company_contact_workspace', {});
      requireCurrent();
      if (directory is! List) { throw StateError('登録会社を確認できません。'); }
      final ids = <String>{};
      for (final raw in directory) {
        if (raw is! Map || raw['id'] is! String || raw['name'] is! String ||
            !const {'customer', 'subcontractor', 'both'}.contains(raw['trade_role']) ||
            (raw['id'] as String).isEmpty || (raw['name'] as String).trim().isEmpty ||
            !ids.add(raw['id'] as String)) {
          throw StateError('登録会社の所属を確認できません。');
        }
        parties.add(TradeDocumentsHubParty(id: raw['id'] as String,
          name: raw['name'] as String, role: raw['trade_role'] as String));
      }
    }
    requireCurrent();
    final next = TradeDocumentsHubSnapshot(companyId: company, role: role,
      availability: availability, parties: List.unmodifiable(parties));
    _snapshot = next;
    notifyListeners();
    return next;
  }

  Future<void> refreshOperation(String companyId, String partyId, bool acceptance) async {
    final value = await load(); requireCurrent();
    if (value.companyId != companyId || !value.availability.enabled ||
        value.parties.where((p) => p.id == partyId && p.permits(acceptance)).length != 1) {
      throw StateError('注文・請書の利用状態が変わりました。開き直してください。');
    }
  }
  void requireOperation(String companyId, String partyId, bool acceptance) {
    requireCurrent(); final value = _snapshot;
    if (value == null || value.companyId != companyId || !value.availability.enabled ||
        value.parties.where((p) => p.id == partyId && p.permits(acceptance)).length != 1) {
      throw StateError('注文・請書の利用状態が変わりました。開き直してください。');
    }
  }
  @override void dispose() {
    if (_closed) { return; }
    _closed = true; _snapshot = null;
    _session.removeListener(_changed); _session.dispose(); super.dispose();
  }
}

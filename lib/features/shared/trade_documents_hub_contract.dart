/// The standalone generator is independent of site-order archive availability.
/// Missing, partial or future contracts never enable a new operation.
class TradeDocumentsHubAvailability {
  const TradeDocumentsHubAvailability({required this.supported, required this.enabled});
  final bool supported;
  final bool enabled;
  static const unavailable = TradeDocumentsHubAvailability(supported: false, enabled: false);
  factory TradeDocumentsHubAvailability.fromFlags(Map<String, dynamic> flags) {
    final supported = flags['site_order_documents'] is bool &&
        flags['standalone_trade_documents_contract_version'] == 1 &&
        flags['standalone_trade_documents_contract_version'] is int &&
        flags['trade_documents_master_contract_version'] == 1 &&
        flags['trade_documents_master_contract_version'] is int;
    return TradeDocumentsHubAvailability(supported: supported,
      enabled: supported && flags['site_order_documents'] == true);
  }
}

class TradeDocumentsHubParty {
  const TradeDocumentsHubParty({required this.id, required this.name, required this.role});
  final String id, name, role;
  bool permits(bool acceptance) => (acceptance ? const {'customer', 'both'}
    : const {'subcontractor', 'both'}).contains(role);
}

class TradeDocumentsHubAccess {
  TradeDocumentsHubAccess.fromJson(Object? raw, {
    required String actorId, required String companyId, required String sessionId,
    required String role,
  }) {
    const keys = {'contract_version','actor_id','company_id','session_id','role',
      'master_enabled','can_generate','context_contract_version'};
    if (raw is! Map || raw.length != keys.length || raw.keys.any((k) => !keys.contains(k)) ||
        actorId.isEmpty || companyId.isEmpty || sessionId.isEmpty ||
        raw['contract_version'] is! int || raw['contract_version'] != 1 ||
        raw['actor_id'] != actorId || raw['company_id'] != companyId ||
        raw['session_id'] != sessionId || raw['role'] != role ||
        !const {'owner', 'admin', 'manager'}.contains(role) ||
        raw['master_enabled'] != true || raw['can_generate'] != true ||
        raw['context_contract_version'] is! int || raw['context_contract_version'] != 1) {
      throw StateError('注文・請書の利用権限を確認できません。');
    }
  }
}

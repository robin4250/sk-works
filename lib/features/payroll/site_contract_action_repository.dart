import 'package:supabase_flutter/supabase_flutter.dart';

import 'site_contract_action_coordinator.dart';

class SiteContractActionRepository implements SiteContractActionGateway {
  SiteContractActionRepository(this.client);
  final SupabaseClient client;
  bool _runtimeReady = false;
  String? _capabilityActor;
  Map<String, dynamic>? _capability;
  @override
  String? get actorId => client.auth.currentUser?.id;
  @override
  bool get mutationsEnabled => _runtimeReady && actorId != null && actorId == _capabilityActor;
  @override
  Future<Map<String, dynamic>> workspace(String itemId, String companyId) async =>
    Map<String, dynamic>.from(await client.rpc('site_contract_workspace',
      params: {'p_item': itemId, 'p_company': companyId}) as Map);
  @override
  Future<Map<String, dynamic>> sealPreview(String itemId, String companyId, String? proposalId) async {
    _runtimeReady = false;
    _capability = null;
    final actor = actorId;
    if (actor == null) {
      throw StateError('ログインが必要です。');
    }
    final data = Map<String, dynamic>.from(await client.rpc('preview_site_contract_seal',
      params: {'p_item': itemId, 'p_company': companyId, 'p_proposal': proposalId}) as Map);
    _runtimeReady = actorId == actor && data['atomic_seal_version'] == 1 &&
      data['rollout_enabled'] == true && data['company_id'] == companyId &&
      data['shared_item_id'] == itemId && data['proposal_id'] == proposalId &&
      data['sender_company_id'] is String && data['recipient_company_id'] is String &&
      (data['sender_company_id'] as String).isNotEmpty &&
      (data['recipient_company_id'] as String).isNotEmpty &&
      data['sender_company_id'] != data['recipient_company_id'] &&
      (proposalId == null
        ? data['sender_company_id'] == companyId && data['can_send'] == true
        : data['recipient_company_id'] == companyId && data['can_approve'] == true);
    if (_runtimeReady) {
      _capabilityActor = actor;
      _capability = data;
    }
    return data;
  }
  @override
  Future<String> execute(SiteContractActionDraft draft, Map<String, dynamic> terms) async {
    if (!mutationsEnabled || actorId != draft.actorId ||
        _capability?['revision'] != draft.revision || _capability?['seal_hash'] != draft.sealHash ||
        _capability?['company_id'] != draft.companyId || _capability?['shared_item_id'] != draft.itemId ||
        _capability?['proposal_id'] != (draft.action == SiteContractAction.approve ? draft.proposalId : null)) {
      throw StateError('押印操作は準備中です。');
    }
    // Consume the local capability before awaiting the write; a fresh preview
    // is required after success or uncertainty. Server guards are authoritative.
    _runtimeReady = false;
    if (draft.action == SiteContractAction.send) {
      final id = await client.rpc('send_sealed_site_contract', params: {
        'p_item': draft.itemId, 'p_company': draft.companyId,
        'p_expected_revision': draft.revision, 'p_terms': terms,
        'p_expected_seal_hash': draft.sealHash,
      });
      if (id is! String || id.isEmpty) {
        throw StateError('送信記録を確認できません。');
      }
      return id;
    }
    await client.rpc('approve_sealed_site_contract', params: {
      'p_proposal': draft.proposalId, 'p_company': draft.companyId,
      'p_expected_revision': draft.revision, 'p_expected_seal_hash': draft.sealHash,
    });
    return draft.proposalId;
  }
}

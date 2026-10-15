import 'dart:convert';

import '../../domain/company_seal_snapshot.dart';

enum SiteContractAction { send, approve }
enum SiteContractActionOutcome { success, blocked, stale, unknown, busy }

Object? _ordered(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: _ordered(value[key])};
  }
  if (value is List) {
    return [for (final item in value) _ordered(item)];
  }
  return value;
}
String _canonical(Object? value) => jsonEncode(_ordered(value));

class SiteContractActionDraft {
  SiteContractActionDraft({required this.action, required this.itemId,
    required this.companyId, required this.actorId, required this.proposalId,
    required this.revision, required Map<String, dynamic> terms,
    required Map<String, dynamic> seal, required this.sealHash})
    : terms = Map.unmodifiable(Map<String, dynamic>.from(jsonDecode(jsonEncode(terms)) as Map)),
      seal = Map.unmodifiable(Map<String, dynamic>.from(jsonDecode(jsonEncode(seal)) as Map));
  final SiteContractAction action;
  final String itemId;
  final String companyId;
  final String actorId;
  final String proposalId;
  final int revision;
  final Map<String, dynamic> terms;
  final Map<String, dynamic> seal;
  final String sealHash;
  CompanySealSnapshot get companySeal => CompanySealSnapshot.fromJson(seal);
}

abstract class SiteContractActionGateway {
  String? get actorId;
  bool get mutationsEnabled;
  Future<Map<String, dynamic>> workspace(String itemId, String companyId);
  Future<Map<String, dynamic>> sealPreview(String itemId, String companyId, String? proposalId);
  Future<String> execute(SiteContractActionDraft draft, Map<String, dynamic> terms);
}

/// A preview is never an approval. No automatic retry follows an uncertain write.
class SiteContractActionCoordinator {
  SiteContractActionCoordinator(this.gateway);
  final SiteContractActionGateway gateway;
  bool _busy = false;

  Future<SiteContractActionDraft> prepare(SiteContractAction action,
      String itemId, String companyId) async {
    final actor = gateway.actorId;
    if (actor == null) {
      throw StateError('ログインが必要です。');
    }
    final workspace = await gateway.workspace(itemId, companyId);
    if (!{workspace['parent_company_id'], workspace['child_company_id']}.contains(companyId)) {
      throw StateError('契約当事者を確認できません。');
    }
    final proposals = <Map<String, dynamic>>[
      if (workspace['proposals'] is List)
        for (final raw in workspace['proposals'] as List)
          if (raw is Map && raw['revision'] is int && raw['id'] is String && raw['terms'] is Map)
            Map<String, dynamic>.from(raw),
    ]..sort((a, b) => (b['revision'] as int).compareTo(a['revision'] as int));
    if (proposals.isEmpty) {
      throw StateError('確認できる契約候補がありません。先に既存の金額提案を保存してください。');
    }
    final proposal = proposals.first;
    final preview = await gateway.sealPreview(itemId, companyId,
      action == SiteContractAction.approve ? proposal['id'] as String : null);
    final sender = preview['sender_company_id'];
    final recipient = preview['recipient_company_id'];
    if (preview['atomic_seal_version'] != 1 || preview['rollout_enabled'] != true ||
        sender is! String || recipient is! String || sender.isEmpty || recipient.isEmpty ||
        sender == recipient ||
        !{workspace['parent_company_id'], workspace['child_company_id']}.contains(sender) ||
        !{workspace['parent_company_id'], workspace['child_company_id']}.contains(recipient) ||
        (action == SiteContractAction.send
          ? sender != companyId || preview['can_send'] != true
          : recipient != companyId || preview['can_approve'] != true) ||
        gateway.actorId != actor || preview['company_id'] != companyId ||
        preview['shared_item_id'] != itemId || preview['revision'] != proposal['revision'] ||
        (action == SiteContractAction.approve && preview['proposal_id'] != proposal['id']) ||
        (action == SiteContractAction.send && preview['proposal_id'] != null) ||
        preview['seal_snapshot'] is! Map || preview['seal_hash'] is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(preview['seal_hash'] as String)) {
      throw StateError('対象版・会社印の一致を確認できません。再読み込みしてください。');
    }
    final draft = SiteContractActionDraft(action: action, itemId: itemId,
      companyId: companyId, actorId: actor, proposalId: proposal['id'] as String,
      revision: proposal['revision'] as int, terms: Map<String, dynamic>.from(proposal['terms'] as Map),
      seal: Map<String, dynamic>.from(preview['seal_snapshot'] as Map),
      sealHash: preview['seal_hash'] as String);
    if (draft.companySeal.name.isEmpty) {
      throw StateError('実会社印を確認できません。');
    }
    return draft;
  }

  Future<SiteContractActionOutcome> confirm(SiteContractActionDraft draft, {
    required bool conditionsConfirmed, required bool sealViewed,
    required bool sealConfirmed, String? effectiveFrom,
  }) async {
    if (_busy) {
      return SiteContractActionOutcome.busy;
    }
    if (!gateway.mutationsEnabled || !conditionsConfirmed || !sealViewed || !sealConfirmed) {
      return SiteContractActionOutcome.blocked;
    }
    _busy = true;
    try {
      SiteContractActionDraft fresh;
      try {
        fresh = await prepare(draft.action, draft.itemId, draft.companyId);
      } catch (_) {
        return SiteContractActionOutcome.stale;
      }
      if (fresh.actorId != draft.actorId || fresh.revision != draft.revision ||
          fresh.proposalId != draft.proposalId || fresh.sealHash != draft.sealHash ||
          _canonical(fresh.seal) != _canonical(draft.seal) ||
          _canonical(fresh.terms) != _canonical(draft.terms)) {
        return SiteContractActionOutcome.stale;
      }
      final terms = Map<String, dynamic>.from(draft.terms);
      if (draft.action == SiteContractAction.send) {
        final value = effectiveFrom ?? terms['effective_from']?.toString();
        final start = DateTime.tryParse('${terms['period_start']}');
        final end = DateTime.tryParse('${terms['period_end']}');
        final effective = value == null ? null : DateTime.tryParse(value);
        if (value == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
            effective == null || start == null || end == null ||
            '${effective.year.toString().padLeft(4, '0')}-${effective.month.toString().padLeft(2, '0')}-${effective.day.toString().padLeft(2, '0')}' != value ||
            effective.isBefore(start) || effective.isAfter(end)) {
          return SiteContractActionOutcome.blocked;
        }
        terms['effective_from'] = value;
      }
      try {
        final id = await gateway.execute(draft, terms);
        if (gateway.actorId != draft.actorId) {
          return SiteContractActionOutcome.unknown;
        }
        final saved = await gateway.workspace(draft.itemId, draft.companyId);
        final rows = saved['proposals'];
        if (rows is List) {
          for (final row in rows) {
            if (row is! Map || row['id'] != id ||
                row['revision'] != draft.revision + (draft.action == SiteContractAction.send ? 1 : 0) ||
                _canonical(row['terms']) != _canonical(terms)) {
              continue;
            }
            final seals = row['seals'];
            if (seals is List && seals.any((seal) => seal is Map &&
                seal['company_id'] == draft.companyId && seal['actor_id'] == draft.actorId &&
                seal['action'] == (draft.action == SiteContractAction.send ? 'sent' : 'approved') &&
                _canonical(seal['seal_snapshot']) == _canonical(draft.seal))) {
              return SiteContractActionOutcome.success;
            }
          }
        }
      } catch (_) {
        // The write may have committed. Refresh first; never announce success
        // or repeat a mutation merely because its response was unavailable.
      }
      return SiteContractActionOutcome.unknown;
    } finally {
      _busy = false;
    }
  }
}

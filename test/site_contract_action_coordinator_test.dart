import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/site_contract_action_coordinator.dart';
import 'package:sk_works/features/payroll/site_contract_confirmation_mode.dart';

class FakeContractGateway implements SiteContractActionGateway {
  String actor = 'actor-a';
  bool enabled = true;
  bool unknownWrite = false;
  bool wrongReceiptSeal = false;
  int capabilityVersion = 1;
  bool rollout = true;
  bool allowed = true;
  int writes = 0;
  String hash = List.filled(64, 'a').join();
  final seal = <String, dynamic>{'version': 1, 'style': 'legacy', 'name': '株式会社青空'};
  final terms = <String, dynamic>{'period_start': '2026-10-01',
    'period_end': '2026-10-31', 'effective_from': '2026-10-15',
    'base_amount_yen': 10000, 'final_amount_yen': 10000, 'adjustments': <Object>[]};
  late final List<Map<String, dynamic>> proposals = [
    {'id': 'p1', 'revision': 1, 'terms': terms, 'seals': <Object>[]},
  ];
  @override
  String? get actorId => actor;
  @override
  bool get mutationsEnabled => enabled;
  @override
  Future<Map<String, dynamic>> workspace(String itemId, String companyId) async => {
    'parent_company_id': 'a', 'child_company_id': 'b', 'proposals': proposals,
  };
  @override
  Future<Map<String, dynamic>> sealPreview(String itemId, String companyId, String? proposalId) async => {
    'atomic_seal_version': capabilityVersion, 'rollout_enabled': rollout,
    'sender_company_id': proposalId == null ? companyId : 'b',
    'recipient_company_id': proposalId == null ? 'b' : companyId,
    'can_send': proposalId == null && allowed, 'can_approve': proposalId != null && allowed,
    'company_id': companyId, 'shared_item_id': itemId, 'proposal_id': proposalId,
    'revision': proposals.first['revision'], 'seal_snapshot': seal, 'seal_hash': hash,
  };
  @override
  Future<String> execute(SiteContractActionDraft draft, Map<String, dynamic> chosenTerms) async {
    writes++;
    expect(draft.sealHash, hash);
    expect(chosenTerms['final_amount_yen'], 10000);
    final id = draft.action == SiteContractAction.send ? 'p2' : draft.proposalId;
    proposals.insert(0, {'id': id,
      'revision': draft.revision + (draft.action == SiteContractAction.send ? 1 : 0),
      'terms': Map<String, dynamic>.from(chosenTerms),
      'seals': [{'company_id': draft.companyId, 'actor_id': actor,
        'action': draft.action == SiteContractAction.send ? 'sent' : 'approved',
        'seal_snapshot': wrongReceiptSeal ? {...seal, 'name': '別の印'} : seal}],
    });
    if (unknownWrite) {
      throw TimeoutException('response unavailable after commit');
    }
    return id;
  }
}

Future<SiteContractActionOutcome> confirm(SiteContractActionCoordinator controller,
    SiteContractActionDraft draft, {String? date}) => controller.confirm(draft,
  conditionsConfirmed: true, sealViewed: true, sealConfirmed: true, effectiveFrom: date);

void main() {
  test('sealed mode must be proven; failed or malformed reads are never legacy permission', () {
    expect(siteContractConfirmationMode(null), SiteContractConfirmationMode.unknown);
    expect(siteContractConfirmationMode({'proposals': [{'id': 'p1'}]}), SiteContractConfirmationMode.unknown);
    expect(siteContractConfirmationMode({'proposals': []}), SiteContractConfirmationMode.legacy);
    expect(siteContractConfirmationMode({'proposals': [{'seals': []}]}), SiteContractConfirmationMode.legacy);
    expect(siteContractConfirmationMode({'proposals': [{'seals': [{'action': 'sent'}]}]}), SiteContractConfirmationMode.sealed);
  });

  test('staged feature stays blocked without explicit activation or human checks', () async {
    final gateway = FakeContractGateway();
    final controller = SiteContractActionCoordinator(gateway);
    final draft = await controller.prepare(SiteContractAction.send, 'item', 'a');
    gateway.enabled = false;
    expect(await confirm(controller, draft), SiteContractActionOutcome.blocked);
    gateway.enabled = true;
    expect(await controller.confirm(draft, conditionsConfirmed: true,
      sealViewed: false, sealConfirmed: true), SiteContractActionOutcome.blocked);
    expect(gateway.writes, 0);
  });
  test('changed seal or revision cannot be signed', () async {
    for (final change in ['seal', 'revision', 'actor']) {
      final gateway = FakeContractGateway();
      final controller = SiteContractActionCoordinator(gateway);
      final draft = await controller.prepare(SiteContractAction.send, 'item', 'a');
      if (change == 'seal') {
        gateway.hash = List.filled(64, 'b').join();
      } else if (change == 'revision') {
        gateway.proposals.first['revision'] = 2;
      } else {
        gateway.actor = 'actor-b';
      }
      expect(await confirm(controller, draft), SiteContractActionOutcome.stale);
      expect(gateway.writes, 0);
    }
  });
  test('send success requires matching saved revision terms actor and seal', () async {
    final gateway = FakeContractGateway();
    final controller = SiteContractActionCoordinator(gateway);
    final draft = await controller.prepare(SiteContractAction.send, 'item', 'a');
    expect(await confirm(controller, draft), SiteContractActionOutcome.success);
    expect(gateway.writes, 1);
    expect(gateway.proposals.first['revision'], 2);
    expect(gateway.proposals.first['terms'], gateway.terms);
  });
  test('approve targets the same proposal without creating counterpart approval', () async {
    final gateway = FakeContractGateway();
    final controller = SiteContractActionCoordinator(gateway);
    final draft = await controller.prepare(SiteContractAction.approve, 'item', 'a');
    expect(await confirm(controller, draft), SiteContractActionOutcome.success);
    expect(gateway.proposals.first['id'], 'p1');
    expect((gateway.proposals.first['seals'] as List).length, 1);
    expect(gateway.writes, 1);
  });
  test('unknown response never announces success or automatically retries', () async {
    final gateway = FakeContractGateway()..unknownWrite = true;
    final controller = SiteContractActionCoordinator(gateway);
    final draft = await controller.prepare(SiteContractAction.send, 'item', 'a');
    expect(await confirm(controller, draft), SiteContractActionOutcome.unknown);
    expect(await confirm(controller, draft), SiteContractActionOutcome.stale);
    expect(gateway.writes, 1);
  });
  test('different saved seal never counts as successful confirmation', () async {
    final gateway = FakeContractGateway()..wrongReceiptSeal = true;
    final controller = SiteContractActionCoordinator(gateway);
    final draft = await controller.prepare(SiteContractAction.send, 'item', 'a');
    expect(await confirm(controller, draft), SiteContractActionOutcome.unknown);
  });
  test('missing or invalid apply date stays blocked without invented values', () async {
    final gateway = FakeContractGateway();
    gateway.terms.remove('effective_from');
    final controller = SiteContractActionCoordinator(gateway);
    final draft = await controller.prepare(SiteContractAction.send, 'item', 'a');
    expect(await confirm(controller, draft), SiteContractActionOutcome.blocked);
    expect(await confirm(controller, draft, date: '2026-10-32'), SiteContractActionOutcome.blocked);
    expect(gateway.writes, 0);
    expect(await confirm(controller, draft, date: '2026-10-20'), SiteContractActionOutcome.success);
  });
  test('old backend, OFF or forbidden action cannot produce an executable preview', () async {
    for (final kind in ['old', 'off', 'role']) {
      final gateway = FakeContractGateway();
      if (kind == 'old') {
        gateway.capabilityVersion = 0;
      } else if (kind == 'off') {
        gateway.rollout = false;
      } else {
        gateway.allowed = false;
      }
      await expectLater(SiteContractActionCoordinator(gateway).prepare(SiteContractAction.send, 'item', 'a'),
        throwsStateError);
      expect(gateway.writes, 0);
    }
  });
  test('missing atomic preview hash is not a usable company seal', () async {
    final gateway = FakeContractGateway()..hash = '';
    expect(SiteContractActionCoordinator(gateway).prepare(SiteContractAction.send, 'item', 'a'),
      throwsStateError);
    expect(gateway.writes, 0);
  });
}

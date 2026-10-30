import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/sites/site_order_workflow.dart';

const scope = SiteOrderScope(actorId: 'actor', companyId: 'own', sessionId: 'session', siteId: 'site');
const recipient = SiteOrderRecipient(tradeCompanyId: 'trade', companyId: 'other',
  name: '協力会社', connectionVersion: 3);
SiteOrderArtifact artifact({int revision = 2}) => SiteOrderArtifact(
  id: 'order', companyId: 'own', siteId: 'site', revision: revision,
  pdfSha256: 'a' * 64, title: '工事名称', startsOn: '2026-10-01',
  endsOn: '2026-10-31', sealVersionId: 'registered-seal',
  prices: [SiteOrderPrice(item: 'とび工', unitPriceYen: 32000, unit: '人日')]);
SiteOrderDeliveryReceipt receipt(SiteOrderDeliveryIntent i, {String? hash, String? actor,
  int? connectionVersion}) => SiteOrderDeliveryReceipt(requestId: i.requestId,
  companyId: i.scope.companyId, siteId: i.scope.siteId, artifactId: i.artifact.id,
  artifactRevision: i.artifact.revision, pdfSha256: hash ?? i.artifact.pdfSha256,
  recipientCompanyId: i.recipient.companyId, deliveryId: 'delivery',
  actorId: actor ?? i.scope.actorId, sessionId: i.scope.sessionId,
  recipientConnectionVersion: connectionVersion ?? i.recipient.connectionVersion);

void main() {
  late SiteOrderScope current;
  late bool artifactCurrent, recipientCurrent;
  late List<SiteOrderDeliveryIntent> persisted;
  late SiteOrderSendWorkflow workflow;
  setUp(() {
    current = scope; artifactCurrent = true; recipientCurrent = true;
    persisted = [];
    workflow = SiteOrderSendWorkflow(scope: scope, artifact: artifact(),
      currentScope: () => current, isArtifactCurrent: (_) => artifactCurrent,
      isRecipientCurrent: (_) => recipientCurrent, newRequestId: () => 'one-request',
      persistIntent: (i) async { persisted.add(i); });
  });
  void confirm() { workflow.select(recipient); workflow.confirm(); }

  test('no network write before recipient and explicit second confirmation', () async {
    var calls = 0;
    await expectLater(workflow.send((i) async { calls++; return receipt(i); }), throwsStateError);
    workflow.select(recipient);
    expect(calls, 0); expect(persisted, isEmpty);
    workflow.confirm();
    await workflow.send((i) async { expect(persisted.single, same(i)); calls++; return receipt(i); });
    expect(calls, 1); expect(workflow.state, SiteOrderSendState.sent);
    await expectLater(workflow.send((i) async { calls++; return receipt(i); }), throwsStateError);
    expect(calls, 1);
  });
  test('empty scope and empty recipient identity rejected', () {
    expect(() => SiteOrderSendWorkflow(scope: const SiteOrderScope(actorId: '', companyId: 'own',
      sessionId: 'session', siteId: 'site'), artifact: artifact(), currentScope: () => scope,
      isArtifactCurrent: (_) => true, isRecipientCurrent: (_) => true,
      newRequestId: () => 'id', persistIntent: (_) async {}), throwsStateError);
    expect(() => workflow.select(const SiteOrderRecipient(tradeCompanyId: 'trade',
      companyId: '', name: 'name', connectionVersion: 1)), throwsStateError);
  });
  test('company or session change before send never writes', () async {
    confirm(); current = const SiteOrderScope(actorId: 'actor', companyId: 'own',
      sessionId: 'different-session', siteId: 'site');
    var calls = 0;
    await expectLater(workflow.send((i) async { calls++; return receipt(i); }), throwsStateError);
    expect(calls, 0); expect(workflow.state, SiteOrderSendState.retired);
  });
  test('artifact changed after confirmation is rejected', () async {
    confirm(); artifactCurrent = false;
    await expectLater(workflow.send((i) async => receipt(i)), throwsStateError);
    expect(persisted, isEmpty);
  });
  test('recipient disconnected after confirmation is rejected', () async {
    confirm(); recipientCurrent = false;
    await expectLater(workflow.send((i) async => receipt(i)), throwsStateError);
    expect(persisted, isEmpty);
  });
  test('unknown outcome retains intent and never issues a second mutation', () async {
    confirm(); var calls = 0;
    await expectLater(workflow.send((i) async { calls++; throw TimeoutException('timeout'); }),
      throwsA(isA<TimeoutException>()));
    final pending = workflow.pendingIntent;
    expect(workflow.state, SiteOrderSendState.outcomeUnknown);
    expect(() => workflow.select(recipient), throwsStateError);
    expect(() => workflow.confirm(), throwsStateError);
    await expectLater(workflow.send((i) async { calls++; return receipt(i); }), throwsStateError);
    await workflow.resolve((i) async { expect(i, same(pending)); return null; });
    expect(workflow.state, SiteOrderSendState.outcomeUnknown);
    await workflow.resolve((i) async => receipt(i));
    expect(workflow.state, SiteOrderSendState.sent); expect(calls, 1);
  });
  test('foreign actor/hash/recipient revision receipt never confirms success', () async {
    confirm();
    await expectLater(workflow.send((i) async => receipt(i, actor: 'foreign')), throwsStateError);
    expect(workflow.state, SiteOrderSendState.outcomeUnknown);
    await expectLater(workflow.resolve((i) async => receipt(i, hash: 'b' * 64)), throwsStateError);
    await expectLater(workflow.resolve((i) async => receipt(i, connectionVersion: 4)), throwsStateError);
    expect(workflow.receipt, isNull);
  });
  test('session change while awaiting response retires result', () async {
    confirm(); final pending = Completer<SiteOrderDeliveryReceipt>();
    final future = workflow.send((_) => pending.future);
    await Future<void>.delayed(Duration.zero);
    current = const SiteOrderScope(actorId: 'other-actor', companyId: 'own',
      sessionId: 'session', siteId: 'site');
    pending.complete(receipt(workflow.pendingIntent!));
    await expectLater(future, throwsStateError);
    expect(workflow.state, SiteOrderSendState.retired); expect(workflow.receipt, isNull);
  });
  test('double tap during durable intent persistence has one writer', () async {
    final persistedGate = Completer<void>();
    workflow = SiteOrderSendWorkflow(scope: scope, artifact: artifact(),
      currentScope: () => current, isArtifactCurrent: (_) => true,
      isRecipientCurrent: (_) => true, newRequestId: () => 'request',
      persistIntent: (_) => persistedGate.future);
    confirm(); var calls = 0;
    final first = workflow.send((i) async { calls++; return receipt(i); });
    await expectLater(workflow.send((i) async { calls++; return receipt(i); }), throwsStateError);
    persistedGate.complete(); await first; expect(calls, 1);
  });
  test('return to input retires the confirmed artifact', () {
    confirm(); workflow.returnToEditor();
    expect(workflow.state, SiteOrderSendState.retired);
    expect(() => workflow.confirm(), throwsStateError);
  });
  test('invalid calendar day/hash/missing seal/negative price rejected', () {
    expect(() => SiteOrderArtifact(id: 'order', companyId: 'own', siteId: 'site', revision: 1,
      pdfSha256: 'a' * 64, title: 'test', startsOn: '2026-02-30', endsOn: '2026-03-01',
      sealVersionId: 'seal', prices: [SiteOrderPrice(item: 'item', unitPriceYen: 1, unit: '人日')]),
      throwsFormatException);
    expect(() => SiteOrderPrice(item: 'item', unitPriceYen: -1, unit: '人日'), throwsFormatException);
  });
}

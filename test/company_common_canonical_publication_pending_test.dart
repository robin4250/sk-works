import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/company_common_canonical_publication_command.dart';
import 'package:sk_works/features/payroll/company_common_canonical_publication_pending_store.dart';

const actor = '00000000-0000-0000-0000-000000000001';
const otherActor = '00000000-0000-0000-0000-000000000002';
const company = '10000000-0000-0000-0000-000000000001';
const request = '80000000-0000-0000-0000-000000000001';
Map<String, dynamic> commandJson({String requestId = request}) => {
  'p_company_id': company, 'p_payroll_type': 'monthly', 'p_starts_on': '2026-10-01',
  'p_common_version': 3, 'p_common_source': {'version': 1, 'source_hash': 'fixture-only'},
  'p_timeline_version': 0,
  'p_legacy_quantities': [{
    'id': '20000000-0000-0000-0000-000000000001', 'generation': 1,
    'source_unit': '回', 'basis': 'attendance_selected_distinct_dates',
    'aliases': ['合成手当'],
  }],
  'p_individual_reconciliation': CommonPayrollCanonicalPublicationCommand.reconciliation,
  'p_request_id': requestId, 'p_preview_token': 'fixture-preview-hash',
  'p_approve_activation': true,
};
CommonPayrollCanonicalPublicationPending pending({String requestId = request}) =>
    CommonPayrollCanonicalPublicationPending(actorId: actor,
      command: CommonPayrollCanonicalPublicationCommand.fromParams(commandJson(requestId: requestId)));

void main() {
  test('approved command is deeply immutable and receipt lookup retains the same command', () {
    final raw = commandJson();
    final command = CommonPayrollCanonicalPublicationCommand.fromParams(raw);
    (raw['p_common_source'] as Map)['version'] = 99;
    ((raw['p_legacy_quantities'] as List).single as Map)['aliases'] = ['changed'];
    expect((command.params['p_common_source'] as Map)['version'], 1);
    expect(((command.params['p_legacy_quantities'] as List).single as Map)['aliases'], ['合成手当']);
    expect(() => command.params['p_request_id'] = 'changed', throwsUnsupportedError);
    expect(command.receiptParams['p_expected_command'], command.params);
    expect(command.receiptParams['p_request_id'], request);
  });
  test('different schema, owner, request identity and unsupported quantities fail closed', () {
    final saved = pending().toJson();
    expect(() => CommonPayrollCanonicalPublicationPending.parse({...saved, 'kind': 'company_common_allowance_save'}), throwsFormatException);
    expect(() => CommonPayrollCanonicalPublicationPending.parse({...saved, 'company_id': otherActor}), throwsFormatException);
    expect(() => CommonPayrollCanonicalPublicationPending.parse({...saved, 'request_id': otherActor}), throwsFormatException);
    final raw = commandJson();
    ((raw['p_legacy_quantities'] as List).single as Map)['basis'] = 'all_working_dates';
    expect(() => CommonPayrollCanonicalPublicationCommand.fromParams(raw), throwsFormatException);
  });
  test('credentials cannot be placed inside a pending command', () {
    for (final key in ['access_token', 'refresh_token', 'Authorization', 'service_role_key', 'jwt']) {
      final raw = commandJson();
      (raw['p_common_source'] as Map)[key] = 'fixture-not-a-real-secret';
      expect(() => CommonPayrollCanonicalPublicationCommand.fromParams(raw), throwsFormatException);
    }
  });
  test('publish record survives app recreation and only matching verified command clears it', () async {
    final root = await Directory.systemTemp.createTemp('common-publish-fixture-');
    addTearDown(() => root.delete(recursive: true));
    FileCommonPayrollCanonicalPublicationPendingStore store() =>
        FileCommonPayrollCanonicalPublicationPendingStore(currentActor: () => actor, directory: () async => root);
    await store().write(pending());
    final restored = await store().read(actor, company);
    expect(restored!.toJson(), pending().toJson());
    expect(restored.command.receiptParams, pending().command.receiptParams);
    await expectLater(store().write(pending()), throwsStateError);
    await expectLater(store().clear(pending(requestId: otherActor)), throwsStateError);
    final changed = commandJson()..['p_preview_token'] = 'different-approved-preview';
    final sameIdDifferentPayload = CommonPayrollCanonicalPublicationPending(actorId: actor,
      command: CommonPayrollCanonicalPublicationCommand.fromParams(changed));
    await expectLater(store().clear(sameIdDifferentPayload), throwsStateError);
    expect(await store().read(actor, company), isNotNull);
    await store().clear(restored);
    expect(await store().read(actor, company), isNull);
  });
  test('a record transplanted from another actor cannot be read or removed', () async {
    final root = await Directory.systemTemp.createTemp('common-publish-fixture-');
    addTearDown(() => root.delete(recursive: true));
    final store = FileCommonPayrollCanonicalPublicationPendingStore(currentActor: () => actor, directory: () async => root);
    await store.write(pending());
    final folder = Directory('${root.path}/company-common-payroll-publication-pending-v2');
    final file = (await folder.list().where((x) => x.path.endsWith('.json')).toList()).single as File;
    final foreign = pending().toJson()..['actor_id'] = otherActor;
    await file.writeAsString(jsonEncode(foreign));
    await expectLater(store.read(actor, company), throwsFormatException);
    await expectLater(store.clear(pending()), throwsFormatException);
    expect(jsonDecode(await file.readAsString())['actor_id'], otherActor);
  });
  test('account separation and concurrent writes retain the first approved request', () async {
    final root = await Directory.systemTemp.createTemp('common-publish-fixture-');
    addTearDown(() => root.delete(recursive: true));
    var current = actor;
    final store = FileCommonPayrollCanonicalPublicationPendingStore(currentActor: () => current, directory: () async => root);
    final writes = await Future.wait([
      store.write(pending()).then((_) => true, onError: (Object _) => false),
      store.write(pending(requestId: otherActor)).then((_) => true, onError: (Object _) => false),
    ]);
    expect(writes.where((x) => x).length, 1);
    current = otherActor;
    await expectLater(store.read(actor, company), throwsStateError);
    expect(await store.read(otherActor, company), isNull);
    current = actor;
    expect(await store.read(actor, company), isNotNull);
  });
  test('interrupted atomic write recovers; malformed or ambiguous records are retained', () async {
    final root = await Directory.systemTemp.createTemp('common-publish-fixture-');
    addTearDown(() => root.delete(recursive: true));
    final store = FileCommonPayrollCanonicalPublicationPendingStore(currentActor: () => actor, directory: () async => root);
    await store.write(pending());
    final folder = Directory('${root.path}/company-common-payroll-publication-pending-v2');
    final file = (await folder.list().where((x) => x.path.endsWith('.json')).toList()).single as File;
    await file.rename('${file.path}.tmp');
    expect((await store.read(actor, company))!.command.requestId, request);
    await File('${file.path}.tmp').writeAsString(jsonEncode(pending().toJson()));
    await expectLater(store.read(actor, company), throwsStateError);
    expect(await file.exists(), true);
    await File('${file.path}.tmp').delete();
    await file.writeAsString('{damaged');
    await expectLater(store.read(actor, company), throwsFormatException);
    expect(await file.readAsString(), '{damaged');
  });
}
